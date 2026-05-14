import Foundation

/// Shared JSON coders for on-disk caches that traffic in `Date`s. ISO8601 with
/// fractional seconds matches the rest of MengoDesktop's timestamp wire format.
extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
