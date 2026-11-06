/// Where a line sits inside a run of related lines, such as a code block or block quote.
///
/// The app uses this to round only the outer corners of a code block background, and
/// to keep spacing tight between lines of the same block.
public enum BlockPosition: Hashable, Sendable {
    case none
    case single
    case first
    case middle
    case last

    public var isFirst: Bool { self == .single || self == .first }
    public var isLast: Bool { self == .single || self == .last }
}
