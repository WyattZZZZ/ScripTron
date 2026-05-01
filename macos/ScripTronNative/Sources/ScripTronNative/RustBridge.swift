import Foundation

@_silgen_name("scriptron_init")
private func scriptron_init() -> UnsafeMutablePointer<CChar>?

@_silgen_name("scriptron_call")
private func scriptron_call(_ request: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("scriptron_free_string")
private func scriptron_free_string(_ pointer: UnsafeMutablePointer<CChar>?)

struct RpcEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
}

struct EmptyResult: Decodable {}

struct FileEntry: Identifiable, Decodable {
    var id: String { path }
    let name: String
    let path: String
    let is_dir: Bool
    let is_tron: Bool
}

struct TronCell: Codable, Identifiable {
    var id = UUID()
    var run: Bool
    var content: String

    enum CodingKeys: String, CodingKey {
        case run
        case content
    }
}

struct TronFile: Decodable {
    let path: String
    let cells: [TronCell]
    let blackboard: AnyCodable
}

struct ActiveConfig: Decodable {
    let provider: String
    let model: String
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues(AnyCodable.init))
        default:
            try container.encodeNil()
        }
    }
}

final class RustBridge {
    static let shared = RustBridge()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func initialize() throws {
        let response = readCString(scriptron_init())
        let envelope = try decoder.decode(RpcEnvelope<AnyCodable>.self, from: Data(response.utf8))
        if !envelope.ok {
            throw BridgeError.runtime(envelope.error ?? "Unknown initialization failure")
        }
    }

    func call<T: Decodable>(_ method: String, params: [String: Any] = [:], as type: T.Type = T.self) throws -> T {
        let payload: [String: Any] = [
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let request = String(data: data, encoding: .utf8) ?? "{}"
        let response = request.withCString { pointer in
            readCString(scriptron_call(pointer))
        }
        let envelope = try decoder.decode(RpcEnvelope<T>.self, from: Data(response.utf8))
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw BridgeError.runtime(envelope.error ?? "Unknown Rust error")
    }

    private func readCString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return #"{"ok":false,"error":"Rust returned null"}"# }
        defer { scriptron_free_string(pointer) }
        return String(cString: pointer)
    }

    enum BridgeError: LocalizedError {
        case runtime(String)

        var errorDescription: String? {
            switch self {
            case .runtime(let message): message
            }
        }
    }
}

