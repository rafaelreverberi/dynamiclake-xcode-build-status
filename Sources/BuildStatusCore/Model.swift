import Foundation
import CoreFoundation
import CryptoKit

public let pluginIdentifier = "com.dynamiclake.plugins.xcode-build-status"

public struct Settings: Equatable {
    public var success: Double = 3
    public var failure: Double = 5
    public init(values: [String: Any] = [:]) {
        success = Self.duration(values["successDisplaySeconds"], fallback: 3)
        failure = Self.duration(values["failureDisplaySeconds"], fallback: 5)
    }
    public static func duration(_ value: Any?, fallback: Double) -> Double {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return fallback }
        return min(10, max(1, number.doubleValue.rounded()))
    }
    public static func decode(_ data: Data) -> Settings? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["schemaVersion"] as? Int == 1,
              obj["identifier"] as? String == pluginIdentifier,
              let values = obj["values"] as? [String: Any] else { return nil }
        return Settings(values: values)
    }
}

public func historyKey(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

public struct DurationHistory: Codable {
    public var mean: Double
    public var deviation: Double
    public var count: Int
    public var updated: Double
    public init(duration: Double, now: Double) {
        mean = duration; deviation = 0; count = 1; updated = now
    }
    public mutating func learn(_ duration: Double, now: Double) {
        guard duration.isFinite, (0.2...7200).contains(duration) else { return }
        deviation = 0.3 * abs(duration - mean) + 0.7 * deviation
        mean = 0.3 * duration + 0.7 * mean
        count = min(1000, count + 1); updated = now
    }
    public var estimate: Double? {
        guard mean.isFinite, deviation.isFinite, (0.2...7200).contains(mean),
              count > 0, deviation >= 0, deviation <= mean * 0.6 else { return nil }
        return mean
    }
}

public enum ResultState: String { case success, failed, cancelled, unknown }
public struct BuildRecord {
    public var id: String
    public var start: Double
    public var end: Double
    public var result: ResultState
    public var filename: String
    public var scheme: String
    public init(id: String, start: Double, end: Double, result: ResultState, filename: String, scheme: String) {
        self.id = id; self.start = start; self.end = end; self.result = result; self.filename = filename; self.scheme = scheme
    }
}

public enum ManifestParser {
    public static func parse(_ data: Data) throws -> [BuildRecord] {
        guard let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let logs = obj["logs"] as? [String: [String: Any]] else { throw ParseError.invalid }
        return logs.compactMap { key, log in
            guard log["className"] as? String == "IDEActivityLogSection",
                  log["domainType"] as? String == "Xcode.IDEActivityLogDomainType.BuildLog",
                  let id = log["uniqueIdentifier"] as? String, id == key,
                  let filename = log["fileName"] as? String,
                  UUID(uuidString: id) != nil, filename == id + ".xcactivitylog",
                  let start = log["timeStartedRecording"] as? Double,
                  let end = log["timeStoppedRecording"] as? Double,
                  start.isFinite, end.isFinite, end >= start, end > 0 else { return nil }
            let primary = log["primaryObservable"] as? [String: Any] ?? [:]
            let status = primary["highLevelStatus"] as? String ?? ""
            let errors = primary["totalNumberOfErrors"] as? Int
            let result: ResultState
            // Observed Xcode 27 statuses: S (success), W (warnings), E (errors), C (cancelled).
            // Never infer success from the absence of a log or an unrecognized status.
            if status == "C" { result = .cancelled }
            else if status == "E" || (errors ?? 0) > 0 { result = .failed }
            else if ["S", "W"].contains(status), errors == 0 { result = .success }
            else { result = .unknown }
            return BuildRecord(id: id, start: start + Date.timeIntervalBetween1970AndReferenceDate,
                               end: end + Date.timeIntervalBetween1970AndReferenceDate,
                               result: result, filename: filename,
                               scheme: log["schemeIdentifier-schemeName"] as? String ?? "")
        }.sorted { $0.start < $1.start }
    }
}
public enum ParseError: Error { case invalid, limit, unsupported }

/// A cached request describes the build whose SQLite journal has just appeared.
/// Fail closed for command-line, dry-run, index and preview requests.
public struct BuildRequest {
    public let bucket: String
    public static func parse(_ data: Data) -> BuildRequest? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              o["enableIndexBuildArena"] as? Bool == false,
              o["useDryRun"] as? Bool == false,
              let command = o["buildCommand"] as? [String: Any], command["command"] as? String == "build",
              let p = o["parameters"] as? [String: Any],
              let action = p["action"] as? String, ["build", "install", "analyze"].contains(action),
              let config = p["configurationName"] as? String,
              let overrides = p["overrides"] as? [String: Any], overrides["commandLine"] == nil,
              let container = o["containerPath"] as? String else { return nil }
        let synthesized = overrides["synthesized"] as? [String: Any] ?? [:]
        let table = synthesized["table"] as? [String: Any] ?? [:]
        if table["ENABLE_PREVIEWS"] as? String == "YES" { return nil }
        let targetIDs = (o["configuredTargets"] as? [[String: Any]] ?? []).compactMap { $0["guid"] as? String }.sorted()
        guard !targetIDs.isEmpty else { return nil }
        let destination = p["activeRunDestination"] as? [String: Any] ?? [:]
        let identity = [container, config, action, o["schemeCommand"] as? String ?? "",
                        destination["platform"] as? String ?? "", destination["targetArchitecture"] as? String ?? "",
                        targetIDs.joined(separator: ",")].joined(separator: "\u{0}")
        return BuildRequest(bucket: historyKey(identity))
    }
}

public struct ActiveBuild {
    public var started: Double
    public var bucket: String
    public var estimate: Double?
    public var progress: Double = 0
    public init(started: Double, bucket: String, estimate: Double?) {
        self.started = started; self.bucket = bucket; self.estimate = estimate
    }
    public mutating func value(now: Double) -> Double? {
        guard let estimate, estimate.isFinite, estimate > 0 else { return nil }
        let elapsed = max(0, now - started)
        // An unexpectedly long build loses its estimate rather than sitting at 95% forever.
        guard elapsed <= max(10, estimate * 2.5) else { return nil }
        progress = max(progress, min(0.95, elapsed / estimate))
        return progress
    }
}

/// One state machine per DerivedData project. Repeated filesystem events cannot restart timers.
public struct BuildMachine {
    public var active: ActiveBuild?
    public var completed: ResultState?
    public var completedAt: Double?
    public var detail = ""
    public var seen: Set<String> = []
    public let launched: Double
    public init(launched: Double) { self.launched = launched }
    @discardableResult public mutating func begin(now: Double, bucket: String, estimate: Double?) -> Bool {
        guard active == nil else { return false }
        active = ActiveBuild(started: now, bucket: bucket, estimate: estimate)
        completed = nil; completedAt = nil; detail = ""
        return true
    }
    public func accepts(_ record: BuildRecord) -> Bool {
        guard !seen.contains(record.id), record.end >= launched, record.end >= record.start else { return false }
        guard let active else { return false }
        // Journal appears slightly after the recorded start; late logs for older builds must not end a newer one.
        return record.start >= active.started - 5 && record.start <= active.started + 1 && record.end >= active.started
    }
    @discardableResult public mutating func finish(_ record: BuildRecord, now: Double, error: String = "") -> Bool {
        guard accepts(record) else { return false }
        seen.insert(record.id)
        if seen.count > 256 { seen = [record.id] }
        active = nil
        completed = [.success, .failed].contains(record.result) ? record.result : nil
        completedAt = completed == nil ? nil : now
        detail = record.result == .failed ? sanitizeError(error) : ""
        return true
    }
    public mutating func cancel() { active = nil; completed = nil; completedAt = nil; detail = "" }
    /// Failure remains available on hover until new work or lifecycle cleanup replaces it.
    /// Only success has a dismissal deadline; failure duration controls automatic presentation.
    public func dismissalDeadline(settings: Settings) -> Double? {
        guard completed == .success, let completedAt else { return nil }
        return completedAt + settings.success
    }
    public mutating func expire(now: Double, settings: Settings) -> Bool {
        guard let deadline = dismissalDeadline(settings: settings) else { return false }
        if now >= deadline { cancel(); return true }
        return false
    }
}

/// No source lines or absolute paths are transported. Potential secrets suppress detail entirely.
public func sanitizeError(_ input: String) -> String {
    var text = input.precomposedStringWithCanonicalMapping
    if text.range(of: "(?i)(token|password|secret|api[_ -]?key|authorization|bearer|credential)", options: .regularExpression) != nil { return "" }
    text = text.replacingOccurrences(of: "(?:file://)?(?:~)?/[^\\s\"'<>]+", with: "[path]", options: .regularExpression)
    text = text.replacingOccurrences(of: "[\\p{Cc}\\p{Cf}]", with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.count > 160 ? String(text.prefix(159)) + "…" : text
}
