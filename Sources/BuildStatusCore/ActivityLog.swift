import Foundation

/// Narrow, bounded SLF reader. This is intentionally not a general XCLogParser replacement.
/// Extracts only diagnostic message titles and the root cancellation flag; ignores source/command text.
public enum ActivityLog {
    enum Token: Equatable { case integer(UInt64), scalar, string(String), className(String), object(String), list(Int), null }
    public struct Summary { public var cancelled: Bool; public var error: String }
    public static func parse(_ data: Data, rootID: String) throws -> Summary {
        guard data.count <= 16_000_000, data.starts(with: Data("SLF0".utf8)) else { throw ParseError.limit }
        let bytes = Array(data)
        var position = 4
        var classes: [String] = []
        var tokens: [Token] = []
        while position < bytes.count {
            guard tokens.count < 300_000 else { throw ParseError.limit }
            let begin = position
            while position < bytes.count && ((48...57).contains(bytes[position]) || (97...102).contains(bytes[position])) { position += 1 }
            guard position < bytes.count else { throw ParseError.invalid }
            let digits = String(decoding: bytes[begin..<position], as: UTF8.self)
            let delimiter = bytes[position]; position += 1
            switch delimiter {
            case 35: // integer
                guard let n = UInt64(digits) else { throw ParseError.invalid }; tokens.append(.integer(n))
            case 94: // double
                guard digits.count == 16, UInt64(digits, radix: 16) != nil else { throw ParseError.invalid }; tokens.append(.scalar)
            case 34, 37, 42: // UTF-8 string, class name, JSON
                guard let n = Int(digits), n >= 0, n <= bytes.count - position else { throw ParseError.invalid }
                guard let string = String(bytes: bytes[position..<position+n], encoding: .utf8) else { throw ParseError.invalid }
                position += n
                if delimiter == 37 {
                    guard classes.count < 256 else { throw ParseError.limit }; classes.append(string); tokens.append(.className(string))
                } else if delimiter == 42 { tokens.append(.scalar) }
                else { tokens.append(.string(string)) }
            case 64:
                guard let n = Int(digits), n > 0, n <= classes.count else { throw ParseError.invalid }
                tokens.append(.object(classes[n-1]))
            case 40:
                guard let n = Int(digits), n >= 0, n <= 300_000 else { throw ParseError.invalid }; tokens.append(.list(n))
            case 45:
                guard digits.isEmpty else { throw ParseError.invalid }; tokens.append(.null)
            default: throw ParseError.unsupported
            }
        }
        guard case let .integer(version) = tokens.first, version == 13 else { throw ParseError.unsupported }
        // The root section's ID occurs after its cancellation/quiet/cache flags, optional
        // version-specific integer, subtitle, location and command description. Requiring
        // a null root location keeps this narrow parser from guessing unknown class layouts.
        guard let root = tokens.lastIndex(of: .string(rootID)), root >= 7 else { throw ParseError.invalid }
        func stringOrNull(_ t: Token) -> Bool { if case .string = t { return true }; return t == .null }
        guard stringOrNull(tokens[root-1]), tokens[root-2] == .null, stringOrNull(tokens[root-3]) else { throw ParseError.unsupported }
        let flagEnd = root - 4
        // SLF 13 adds a result flag before cancellation/quiet/cache in the root trailer.
        // A failed build sets result=1, cancellation=0; a stopped build sets both to 1.
        guard case let .integer(resultFlag) = tokens[flagEnd-3], resultFlag <= 1 else { throw ParseError.unsupported }
        guard flagEnd >= 2,
              case let .integer(cancelled) = tokens[flagEnd-2], cancelled <= 1,
              case let .integer(quiet) = tokens[flagEnd-1], quiet <= 1,
              case let .integer(cache) = tokens[flagEnd], cache <= 1,
              root + 2 < tokens.count, stringOrNull(tokens[root+1]), stringOrNull(tokens[root+2]) else { throw ParseError.unsupported }
        // Only the observed SLF 13 root layout is accepted. Unknown versions fail closed.
        // A diagnostic title is useful only when its structured severity is error (2).
        var errors: [String] = []
        for i in tokens.indices where i + 7 < tokens.count {
            guard case let .object(name) = tokens[i],
                  ["IDEActivityLogMessage", "IDEDiagnosticActivityLogMessage", "IDEClangDiagnosticActivityLogMessage"].contains(name),
                  case let .string(title) = tokens[i+1], stringOrNull(tokens[i+2]),
                  case .integer = tokens[i+3], case .integer = tokens[i+4], case .integer = tokens[i+5],
                  tokens[i+6] == .null || tokens[i+6] == .list(0), tokens[i+7] == .integer(2) else { continue }
            let safe = sanitizeError(title)
            if !safe.isEmpty { errors.append(safe) }
        }
        let useful = errors.first { !$0.contains("failed with a nonzero exit code") } ?? errors.first ?? ""
        return Summary(cancelled: cancelled == 1, error: useful)
    }
}
