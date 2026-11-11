import Foundation

/// Any JSON value. Hook input differs per tool and may change between Claude Code versions,
/// so it is decoded loosely and read with optional lookups.
public enum JSONValue: Sendable, Hashable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// A string, or a whole number written as a string ("3" for 3).
    public var identifier: String? {
        switch self {
        case .string(let value): value
        case .number(let value) where value == value.rounded(): String(Int(value))
        default: nil
        }
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Every string anywhere inside this value, depth first.
    var allStrings: [String] {
        switch self {
        case .string(let value): [value]
        case .array(let values): values.flatMap(\.allStrings)
        case .object(let object): object.keys.sorted().flatMap { object[$0]!.allStrings }
        default: []
        }
    }
}
