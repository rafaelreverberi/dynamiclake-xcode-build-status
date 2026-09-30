import Foundation

public enum Messages {
    public static func features(_ string: String?) -> Set<String> {
        Set((string ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
    public static func dismiss(id: String) -> [String: Any] {
        ["schemaVersion": 1, "type": "dismiss", "activityID": id, "requestID": UUID().uuidString]
    }
    public static func activity(id: String, create: Bool, result: ResultState? = nil, value: Double? = nil,
                                detail: String = "", duration: Double = 3, features: Set<String> = []) -> [String: Any] {
        let hammer: [String: Any] = ["type": "image", "source": "sfSymbol", "systemImage": "hammer.fill", "tint": "blue"]
        var right: [String: Any] = ["type": "progress", "tint": "blue"]
        var text = value == nil ? "Building" : "Building — Estimated Progress"
        if result == .success || result == .failed {
            right = ["type": "status", "status": result!.rawValue, "tint": result == .success ? "green" : "red"]
            text = result == .success ? "Build Succeeded" : "Build Failed"
            let safe = sanitizeError(detail)
            if result == .failed && !safe.isEmpty { text += " — " + safe }
        } else if let value, value.isFinite { right["value"] = min(0.95, max(0, value)) }
        var message: [String: Any] = ["schemaVersion": 1, "requestID": UUID().uuidString,
            "type": create ? "create" : "update", "activityID": id,
            "surfaces": ["compactLiveActivity": ["leftSlot": hammer, "rightSlot": right],
                         "sneakPeek": ["leftSlot": hammer, "center": ["type": "text", "text": text, "style": "marquee"], "rightSlot": right]]]
        if create { message["title"] = "Xcode Build Status"; message["priority"] = "normal"; message["size"] = "small" }
        if (result == .success || result == .failed) && features.contains("presentSneakPeek") {
            message["presentSneakPeek"] = Settings.duration(duration, fallback: 3)
        }
        return message
    }
    public static func frame(_ message: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        guard data.count <= 64_000 else { throw ParseError.limit }
        var length = UInt32(data.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + data
    }
}
