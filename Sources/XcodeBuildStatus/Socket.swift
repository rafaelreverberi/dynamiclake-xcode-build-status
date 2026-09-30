import Foundation
import Darwin
import BuildStatusCore

final class SocketClient {
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    var disconnected: (() -> Void)?
    init(path: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let encoded = Array(path.utf8) + [UInt8(0)]
        guard encoded.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ParseError.limit }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: encoded) }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ParseError.invalid }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let rc = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if rc != 0 { close(fd); fd = -1; throw ParseError.invalid }
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        readSource?.setEventHandler { [weak self] in self?.receive() }
        readSource?.resume()
    }
    deinit { readSource?.cancel(); if fd >= 0 { close(fd) } }
    func send(_ message: [String: Any]) {
        do {
            let frame = try Messages.frame(message)
            var sent = 0
            try frame.withUnsafeBytes { bytes in
                while sent < bytes.count {
                    let n = Darwin.send(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw ParseError.invalid }
                    sent += n
                }
            }
        } catch { diagnostic("Socket write failed; stopping to avoid stale or corrupt frames."); disconnected?() }
    }
    private func receive() {
        var chunk = [UInt8](repeating: 0, count: 8192)
        let n = recv(fd, &chunk, chunk.count, MSG_DONTWAIT)
        if n < 0 && (errno == EAGAIN || errno == EINTR) { return }
        guard n > 0 else { disconnected?(); return }
        buffer.append(contentsOf: chunk.prefix(Int(n)))
        while buffer.count >= 4 {
            let size = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard size > 0, size <= 64_000 else { diagnostic("Invalid host response frame."); disconnected?(); return }
            guard buffer.count >= Int(size) + 4 else { return }
            let payload = Data(buffer.dropFirst(4).prefix(Int(size)))
            buffer.removeFirst(Int(size) + 4)
            guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                diagnostic("Invalid host response JSON."); disconnected?(); return
            }
            if obj["ok"] as? Bool == false {
                diagnostic("DynamicLake rejected an activity message; stopping. Check host compatibility.")
                disconnected?(); return
            }
        }
    }
}
