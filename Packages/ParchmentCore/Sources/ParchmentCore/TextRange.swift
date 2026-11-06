/// A half-open range of UTF-16 code units, matching how AppKit's `NSRange` counts text.
///
/// The core package uses its own type so it stays free of Foundation and behaves
/// identically on every platform.
public struct TextRange: Hashable, Sendable, CustomStringConvertible {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init(_ range: Range<Int>) {
        self.init(location: range.lowerBound, length: range.count)
    }

    public var upperBound: Int { location + length }
    public var isEmpty: Bool { length == 0 }
    public var range: Range<Int> { location..<upperBound }

    public func contains(_ index: Int) -> Bool {
        index >= location && index < upperBound
    }

    /// True when the ranges overlap, or when an empty range sits inside or at the edge of the other.
    public func touches(_ other: TextRange) -> Bool {
        other.location <= upperBound && location <= other.upperBound
    }

    public var description: String { "{\(location), \(length)}" }
}
