import Foundation

public enum Messages {
    // The icon is used in up to three slots; bound combined base64 data below the 64 KB frame limit.
    public static let maximumIconBytes = 15_500
    public static func leftImage(style: IconStyle, iconPNG: Data? = nil) -> [String: Any] {
        if style == .xcode, let png = iconPNG, png.count <= maximumIconBytes,
           png.starts(with: [0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]) {
            return ["type": "image", "source": "inlineData", "mimeType": "image/png", "base64Data": png.base64EncodedString()]
        }
        return ["type": "image", "source": "sfSymbol", "systemImage": "hammer.fill", "tint": "blue"]
    }
    public static func features(_ string: String?) -> Set<String> {
        Set((string ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
    public static func dismiss(id: String) -> [String: Any] {
        ["schemaVersion": 1, "type": "dismiss", "activityID": id, "requestID": UUID().uuidString]
    }
    public static func activity(id: String, create: Bool, result: ResultState? = nil, value: Double? = nil,
                                detail: String = "", duration: Double = 3, features: Set<String> = [], iconStyle: IconStyle = .hammer, iconPNG: Data? = nil) -> [String: Any] {
        let icon = leftImage(style: iconStyle, iconPNG: iconPNG)
        var right: [String: Any] = ["type": "progress", "tint": "blue"]
        var text = value == nil ? "Building" : "Building — Estimated Progress"
        if result == .success || result == .failed {
            right = ["type": "image", "source": "sfSymbol", "systemImage": result == .success ? "checkmark" : "xmark", "tint": result == .success ? "green" : "red"]
            text = result == .success ? "Build Succeeded" : "Build Failed"
            let safe = sanitizeError(detail)
            if result == .failed && !safe.isEmpty { text += " — " + safe }
        } else if let value, value.isFinite { right["value"] = min(0.95, max(0, value)) }
        // The host can use the compact right slot when minimized. Keep result symbols in the Sneak Peek.
        let compactRight = (result == .success || result == .failed) ? icon : right
        var message: [String: Any] = ["schemaVersion": 1, "requestID": UUID().uuidString,
            "type": create ? "create" : "update", "activityID": id,
            "surfaces": ["compactLiveActivity": ["leftSlot": icon, "rightSlot": compactRight],
                         "sneakPeek": ["leftSlot": icon, "center": ["type": "text", "text": text, "style": "marquee"], "rightSlot": right]]]
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
