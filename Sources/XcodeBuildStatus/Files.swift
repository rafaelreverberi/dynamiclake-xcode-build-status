import Foundation
import CoreServices
import BuildStatusCore
import Darwin

func diagnostic(_ text: String) { fputs("Xcode Build Status: \(text)\n", stderr) }

func boundedRead(_ url: URL, limit: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else { throw ParseError.limit }
    return data
}

// zlib is part of macOS. No shell command or third-party runtime is used to inflate a completed log.
@_silgen_name("gzopen") private func gzopen(_ path: UnsafePointer<CChar>, _ mode: UnsafePointer<CChar>) -> OpaquePointer?
@_silgen_name("gzread") private func gzread(_ file: OpaquePointer, _ buffer: UnsafeMutableRawPointer, _ length: UInt32) -> Int32
@_silgen_name("gzclose") private func gzclose(_ file: OpaquePointer) -> Int32
func readLog(_ url: URL) throws -> Data {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 4_000_000 else { throw ParseError.limit }
    guard let file = gzopen(url.path, "rb") else { throw ParseError.invalid }
    defer { _ = gzclose(file) }
    var data = Data(); var chunk = [UInt8](repeating: 0, count: 32_768)
    while true {
        let count = gzread(file, &chunk, UInt32(chunk.count))
        guard count >= 0 else { throw ParseError.invalid }
        if count == 0 { break }
        guard data.count + Int(count) <= 16_000_000 else { throw ParseError.limit }
        data.append(contentsOf: chunk.prefix(Int(count)))
    }
    return data
}

final class FileEvents {
    private var stream: FSEventStreamRef?
    var changed: ([String], Bool) -> Void
    init(paths: [String], changed: @escaping ([String], Bool) -> Void) throws {
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let owner = Unmanaged<FileEvents>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let dropped = (0..<count).contains { flags[$0] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged) != 0 }
            owner.changed(array, dropped)
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15,
        UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer))
        guard let stream else { throw ParseError.invalid }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil; throw ParseError.invalid }
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
}

final class HistoryStore {
    private(set) var entries: [String: DurationHistory] = [:]
    private let url: URL
    init() {
        url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/XcodeBuildStatus/history.json")
        if let data = try? boundedRead(url, limit: 32_000), let decoded = try? JSONDecoder().decode([String: DurationHistory].self, from: data) {
            let cutoff = Date().timeIntervalSince1970 - 90 * 86400
            entries = decoded.filter { $0.key.count == 64 && $0.value.estimate != nil && $0.value.updated > cutoff }
            if entries.count > 64 { entries = [:] }
        }
    }
    func learn(key: String, duration: Double) {
        guard (0.2...7200).contains(duration), duration.isFinite else { return }
        let now = Date().timeIntervalSince1970
        if entries[key] != nil { entries[key]!.learn(duration, now: now) }
        else { entries[key] = DurationHistory(duration: duration, now: now) }
        if entries.count > 64, let oldest = entries.min(by: { $0.value.updated < $1.value.updated })?.key { entries.removeValue(forKey: oldest) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { diagnostic("Cannot save duration history; estimates will remain session-local.") }
    }
}

/// SQLite's documented RESERVED_LOCK byte. F_GETLK is read-only and never changes the database.
/// Confirms a journal is live rather than an abandoned file left by a crashed build service.
func databaseHasWriter(_ url: URL) -> Bool {
    let fd = open(url.path, O_RDONLY | O_CLOEXEC)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var lock = flock(l_start: 0x40000001, l_len: 1, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
    return fcntl(fd, F_GETLK, &lock) == 0 && lock.l_type != Int16(F_UNLCK) && lock.l_pid > 0
}

func journalIdentity(_ url: URL) -> String? {
    var info = stat()
    guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
    return "\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
}

/// kqueue vnode events also work in temporary directories that FSEvents may exclude.
/// Watching both file and parent covers in-place writes and atomic replacement.
final class SettingsEvents {
    private let url: URL
    private var parent: DispatchSourceFileSystemObject?
    private var file: DispatchSourceFileSystemObject?
    private let changed: () -> Void
    init(url: URL, changed: @escaping () -> Void) {
        self.url = url; self.changed = changed
        let fd = open(url.deletingLastPathComponent().path, O_EVTONLY | O_CLOEXEC)
        if fd >= 0 {
            parent = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            parent?.setCancelHandler { close(fd) }
            parent?.setEventHandler { [weak self] in self?.bindFile(); self?.changed() }
            parent?.resume()
        }
        bindFile()
    }
    private func bindFile() {
        file?.cancel(); file = nil
        let fd = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        file = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        file?.setCancelHandler { close(fd) }
        file?.setEventHandler { [weak self] in
            guard let self else { return }
            if self.file?.data.contains(.rename) == true || self.file?.data.contains(.delete) == true { self.bindFile() }
            self.changed()
        }
        file?.resume()
    }
    deinit { parent?.cancel(); file?.cancel() }
}

/// Resolve against the executable rather than the host working directory. Read at most once per session.
func packagedIcon(executableURL: URL) -> Data? {
    let url = executableURL.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("xcode-icon.png")
    guard let data = try? boundedRead(url, limit: Messages.maximumIconBytes),
          data.starts(with: [0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]) else { return nil }
    return data
}
