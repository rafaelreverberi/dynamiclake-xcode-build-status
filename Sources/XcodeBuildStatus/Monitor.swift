import Foundation
import AppKit
import BuildStatusCore

private final class Project {
    let url: URL
    let id: String
    var machine: BuildMachine
    var signature = ""
    var published = false
    var journal: Bool = false
    var journalToken: String?
    var awaitingUntil: Double?
    var lastManifestStamp: Date?
    var lastProgressAt: Double = 0
    init(_ url: URL, launched: Double) {
        self.url = url; id = "build-" + String(historyKey(url.path).prefix(20))
        machine = BuildMachine(launched: launched)
    }
    var buildData: URL { url.appendingPathComponent("Build/Intermediates.noindex/XCBuildData") }
    var manifest: URL { url.appendingPathComponent("Logs/Build/LogStoreManifest.plist") }
}

final class Monitor {
    private let client: SocketClient
    private let launched = Date().timeIntervalSince1970
    private let history = HistoryStore()
    private let features = Messages.features(ProcessInfo.processInfo.environment["DYNAMICLAKE_PLUGIN_FEATURES"])
    private var projects: [String: Project] = [:]
    private var watcher: FileEvents?
    private var settingsWatcher: SettingsEvents?
    private var timer: DispatchSourceTimer?
    private var debounce: DispatchWorkItem?
    private var observations: [NSObjectProtocol] = []
    private var settings = Settings()
    private var roots: [URL] = []
    private var settingsURL: URL?
    private var pending: Set<String> = []
    private var needsDiscovery = false
    private var warned: Set<String> = []
    init(client: SocketClient) { self.client = client }
    func start() throws {
        let env = ProcessInfo.processInfo.environment
        if let path = env["DYNAMICLAKE_PLUGIN_SETTINGS_PATH"] { settingsURL = URL(fileURLWithPath: path).resolvingSymlinksInPath() }
        if let json = env["DYNAMICLAKE_PLUGIN_SETTINGS_JSON"], let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = Settings(values: obj["values"] as? [String: Any] ?? obj)
        }
        reloadSettings()
        if let settingsURL {
            settingsWatcher = SettingsEvents(url: settingsURL) { [weak self] in
                self?.reloadSettings(); self?.refresh()
            }
        }
        // No activity is recreated merely because DerivedData or a stale journal exists at startup.
        client.send(Messages.dismiss(id: "xcode-build-status"))
        try configure()
        let center = NSWorkspace.shared.notificationCenter
        observations.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.apple.dt.Xcode" else { return }
            do { try self?.configure() } catch { diagnostic("Cannot refresh filesystem observation.") }
        })
        observations.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.apple.dt.Xcode" else { return }
            self?.projects.values.forEach { $0.machine.cancel(); self?.publish($0) }
            self?.scheduleTimer()
        })
    }
    func stop() { for p in projects.values where p.published { client.send(Messages.dismiss(id: p.id)) } }
    private func configure() throws {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode")
        roots = [base.appendingPathComponent("DerivedData")]
        // Read Xcode's global custom location; no project edits or scheme actions.
        if let custom = UserDefaults(suiteName: "com.apple.dt.Xcode")?.string(forKey: "IDECustomDerivedDataLocation"), custom.hasPrefix("/") {
            let url = URL(fileURLWithPath: custom).standardizedFileURL.resolvingSymlinksInPath()
            if !roots.contains(url) { roots.append(url) }
        }
        let paths = roots.map { url -> String in
            var p = url
            while !FileManager.default.fileExists(atPath: p.path), p.path != "/" { p.deleteLastPathComponent() }
            return p.path
        }
        watcher = try FileEvents(paths: Array(Set(paths)), changed: { [weak self] paths, dropped in self?.changed(paths, dropped: dropped) })
        discover(baseline: true)
    }
    private func discover(baseline: Bool) {
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for url in children {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      !["ModuleCache.noindex", "SDKStatCaches.noindex", "CompilationCache.noindex", "SDKExplicitPrecompiledModules"].contains(url.lastPathComponent),
                      projects[url.path] == nil else { continue }
                let p = Project(url, launched: launched)
                projects[url.path] = p
                if baseline {
                    let journalURL = p.buildData.appendingPathComponent("build.db-journal")
                    p.journalToken = journalIdentity(journalURL)
                    p.journal = p.journalToken != nil
                    if p.journal, databaseHasWriter(p.buildData.appendingPathComponent("build.db")),
                       let request = request(p), let birth = try? journalURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       Date().timeIntervalSince1970 - birth.timeIntervalSince1970 < 7200 {
                        _ = p.machine.begin(now: birth.timeIntervalSince1970, bucket: request.bucket, estimate: nil)
                    }
                    if let data = try? boundedRead(p.manifest, limit: 2_000_000), let records = try? ManifestParser.parse(data) { p.machine.seen = Set(records.map(\.id)) }
                    client.send(Messages.dismiss(id: p.id))
                    publish(p)
                    scheduleTimer()
                } else { pending.insert(url.path) }
            }
        }
        // Remove deleted projects after dismissing their activity.
        for (path, p) in projects where !FileManager.default.fileExists(atPath: path) {
            p.machine.cancel(); publish(p); projects.removeValue(forKey: path)
        }
    }
    private func changed(_ paths: [String], dropped: Bool) {
        var relevant = dropped
        if dropped { needsDiscovery = true; pending.formUnion(projects.keys) }
        for path in paths {
            for root in roots where path == root.path || path == root.deletingLastPathComponent().path { needsDiscovery = true; relevant = true }
            guard let root = roots.first(where: { path.hasPrefix($0.path + "/") }) else { continue }
            let relative = String(path.dropFirst(root.path.count + 1))
            guard let name = relative.split(separator: "/").first else { continue }
            let projectPath = root.appendingPathComponent(String(name)).path
            if projects[projectPath] == nil { needsDiscovery = true }
            // Discard the huge volume of object files, source-index writes and package cache events.
            if path.contains("/Logs/Build/") || path.hasSuffix("/Logs/Build") ||
               path.hasSuffix("/XCBuildData/build.db-journal") || path.hasSuffix("/XCBuildData/build.db") ||
               (path.contains("/Build/Intermediates.noindex/XCBuildData/") && (path.hasSuffix(".xcbuilddata") || path.hasSuffix("build-request.json"))) {
                pending.insert(projectPath); relevant = true
            }
        }
        guard relevant else { return }
        // Fixed debounce: a continuing event stream cannot postpone completion indefinitely.
        guard debounce == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
    private func reloadSettings() {
        guard let settingsURL else { return }
        do {
            let data = try boundedRead(settingsURL, limit: 128_000)
            guard let parsed = Settings.decode(data) else { warn("settings", "Invalid settings; retaining the last valid durations."); return }
            settings = parsed
        } catch { /* A missing file at launch or during atomic replacement retains defaults/last valid values. */ }
    }
    private func warn(_ key: String, _ message: String) { if warned.insert(key).inserted { diagnostic(message) } }
    private func refresh() {
        debounce = nil
        if needsDiscovery { needsDiscovery = false; discover(baseline: false) }
        let now = Date().timeIntervalSince1970
        let keys = pending; pending.removeAll()
        for key in keys { if let p = projects[key] { evaluate(p, now: now) } }
        for p in projects.values { _ = p.machine.expire(now: now, settings: settings); publish(p) }
        scheduleTimer()
    }
    private func request(_ p: Project) -> BuildRequest? {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: p.buildData, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        let latest = folders.filter { $0.pathExtension == "xcbuilddata" }.max {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        guard let latest, let data = try? boundedRead(latest.appendingPathComponent("build-request.json"), limit: 256_000) else { return nil }
        return BuildRequest.parse(data)
    }
    private func evaluate(_ p: Project, now: Double) {
        let token = journalIdentity(p.buildData.appendingPathComponent("build.db-journal"))
        let hasJournal = token != nil
        if hasJournal && token != p.journalToken {
            if databaseHasWriter(p.buildData.appendingPathComponent("build.db")), let request = request(p) {
                // A replacement journal identifies a new build even if FSEvents coalesced deletion/creation.
                if p.machine.active != nil { complete(p, now: now); p.machine.cancel() }
                _ = p.machine.begin(now: now, bucket: request.bucket, estimate: history.entries[request.bucket]?.estimate)
                p.awaitingUntil = nil
            }
        }
        // Request creation may arrive just after the journal; leave the edge pending until metadata is available.
        if !hasJournal || p.machine.active != nil { p.journal = hasJournal; p.journalToken = token }
        if !hasJournal && p.machine.active != nil && p.awaitingUntil == nil { p.awaitingUntil = now + 5 }
        complete(p, now: now)
        if let deadline = p.awaitingUntil, now >= deadline {
            p.machine.cancel(); p.awaitingUntil = nil
            warn("completion", "A build ended without readable final metadata; dismissing without an invented result.")
        }
        if let active = p.machine.active, now - active.started > 7200 { p.machine.cancel(); p.awaitingUntil = nil }
        publish(p)
    }
    private func complete(_ p: Project, now: Double) {
        guard let stamp = try? p.manifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return }
        // Retry a delayed log while awaiting final metadata even if the manifest timestamp is unchanged.
        guard stamp != p.lastManifestStamp || p.awaitingUntil != nil else { return }
        guard let data = try? boundedRead(p.manifest, limit: 2_000_000), let records = try? ManifestParser.parse(data) else {
            warn("manifest", "Build manifest unavailable or unsupported; waiting for a later filesystem event."); return
        }
        p.lastManifestStamp = stamp
        for var record in records where !p.machine.seen.contains(record.id) {
            guard (record.start >= launched || (p.machine.active?.started ?? now) < launched), record.end <= now + 1 else { p.machine.seen.insert(record.id); continue }
            // A very short build can finish within one FSEvents batch. Still show its real completion.
            if p.machine.active == nil && record.start >= (p.machine.completedAt ?? launched) && now - record.end <= 5 {
                _ = p.machine.begin(now: record.start, bucket: "", estimate: nil)
            }
            guard p.machine.accepts(record) else { continue }
            let logURL = p.manifest.deletingLastPathComponent().appendingPathComponent(record.filename)
            var detail = ""
            do {
                let summary = try ActivityLog.parse(readLog(logURL), rootID: record.id)
                if summary.cancelled { record.result = .cancelled }
                detail = summary.error
            } catch {
                if p.awaitingUntil == nil { p.awaitingUntil = now + 5 }
                if now < p.awaitingUntil! { continue }
                record.result = .unknown
                warn("log", "Final activity log is oversized or unsupported; dismissing without guessing cancellation or success.")
            }
            let bucket = p.machine.active?.bucket ?? ""
            if p.machine.finish(record, now: now, error: detail) {
                if record.result == .success && !bucket.isEmpty { history.learn(key: bucket, duration: record.end - record.start) }
                p.awaitingUntil = nil
                publish(p, completion: true)
            }
        }
    }
    private func publish(_ p: Project, completion: Bool = false) {
        let now = Date().timeIntervalSince1970
        var value: Double?
        if p.machine.active != nil { value = p.machine.active!.value(now: now) }
        guard p.machine.active != nil || p.machine.completed != nil else {
            if p.published { client.send(Messages.dismiss(id: p.id)); p.published = false; p.signature = "" }
            return
        }
        // Quantize to one percent and emit at most one progress update per second.
        if let v = value { value = floor(v * 100) / 100 }
        let iconSignature = settings.iconStyle.rawValue
        let signature = "\(iconSignature)|\(p.machine.completed?.rawValue ?? "active")|\(value.map(String.init(describing:)) ?? "indeterminate")|\(p.machine.detail)"
        guard completion || signature != p.signature else { return }
        if p.machine.active != nil && p.published && p.signature.contains("|active|") && now - p.lastProgressAt < 1 { return }
        p.lastProgressAt = now
        let duration = p.machine.completed == .failed ? settings.failure : settings.success
        client.send(Messages.activity(id: p.id, create: !p.published, result: p.machine.completed, value: value,
                                     detail: p.machine.detail, duration: duration, features: completion ? features : [], iconStyle: settings.iconStyle))
        p.published = true; p.signature = signature
    }
    private func scheduleTimer() {
        timer?.cancel(); timer = nil
        let now = Date().timeIntervalSince1970
        var deadlines: [Double] = []
        for p in projects.values {
            if p.machine.active != nil || p.awaitingUntil != nil { deadlines.append(now + 1) }
            if let deadline = p.machine.dismissalDeadline(settings: settings) {
                deadlines.append(deadline)
            }
        }
        guard let next = deadlines.min() else { return }
        timer = DispatchSource.makeTimerSource(queue: .main)
        timer?.schedule(deadline: .now() + max(0.01, next - now), leeway: .milliseconds(30))
        timer?.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSince1970
            for p in self.projects.values {
                if p.awaitingUntil != nil { self.evaluate(p, now: now) }
                if let active = p.machine.active, now - active.started > 7200 { p.machine.cancel() }
                _ = p.machine.expire(now: now, settings: self.settings)
                self.publish(p)
            }
            self.scheduleTimer()
        }
        timer?.resume()
    }
}
