import Foundation
import ParchmentCore

/// Which block background a line needs, stored as the `parchmentBlock` attribute.
nonisolated struct BlockDecoration: OptionSet, Sendable {
    let rawValue: Int

    static let code = BlockDecoration(rawValue: 1 << 0)
    static let quote = BlockDecoration(rawValue: 1 << 1)
    static let isFirst = BlockDecoration(rawValue: 1 << 2)
    static let isLast = BlockDecoration(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Empty for lines that are neither code nor quote.
    init(lineKind: LineKind, position: BlockPosition) {
        var result: BlockDecoration = []
        if lineKind.isCodeBlock {
            result.insert(.code)
        } else if lineKind == .quote {
            result.insert(.quote)
        } else {
            self = []
            return
        }
        if position.isFirst { result.insert(.isFirst) }
        if position.isLast { result.insert(.isLast) }
        self = result
    }

    /// Decodes a `parchmentBlock` attribute value; nil when it is missing or not a number.
    init?(attributeValue: Any?) {
        guard let number = attributeValue as? NSNumber else { return nil }
        self.init(rawValue: number.intValue)
    }

    var number: NSNumber { NSNumber(value: rawValue) }
}
