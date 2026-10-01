import Foundation
import Darwin
import BuildStatusCore

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--inspect-log" {
    do {
        let summary = try ActivityLog.parse(readLog(URL(fileURLWithPath: CommandLine.arguments[2])), rootID: CommandLine.arguments[3])
        print("cancelled=\(summary.cancelled) error=\(summary.error)")
        exit(0)
    } catch { diagnostic("Unsupported or invalid completed log."); exit(1) }
}
if CommandLine.arguments.contains("--check") {
    print("Xcode Build Status: native macOS runtime available")
    exit(0)
}
guard let path = ProcessInfo.processInfo.environment["DYNAMICLAKE_JSON_SOCKET"], path.hasPrefix("/") else {
    diagnostic("Launch this plugin from DynamicLake; DYNAMICLAKE_JSON_SOCKET is required.")
    exit(1)
}
do {
    let client = try SocketClient(path: path)
    let monitor = Monitor(client: client)
    client.disconnected = { exit(1) }
    try monitor.start()
    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
    let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    for source in [term, interrupt] { source.setEventHandler { monitor.stop(); exit(0) }; source.resume() }
    withExtendedLifetime((client, monitor, term, interrupt)) { RunLoop.main.run() }
} catch {
    diagnostic("Cannot initialize the local socket or filesystem watcher.")
    exit(1)
}
