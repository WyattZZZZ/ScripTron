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

struct TronCell: Codable, Identifiable, Equatable {
    var id = UUID()
    var run: Bool
    var content: String

    enum CodingKeys: String, CodingKey {
        case run
        case content
    }

    init(run: Bool, content: String) {
        self.run = run
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        run = try container.decode(Bool.self, forKey: .run)
        content = try container.decode(String.self, forKey: .content)
        id = UUID()
    }
}

struct TronFile: Decodable {
    let path: String
    let cells: [TronCell]
    let blackboard: AnyCodable
}

struct RunEvent: Identifiable, Decodable {
    var id = UUID()
    let type: String
    let content: AnyCodable?
    let tool: String?
    let args: AnyCodable?
    let output: String?
    let success: Bool?
    let step_id: String?
    let attempt: Int?
    let decision: String?
    let reason: String?
    let error: String?
    let skills: [String]?

    static func local(type: String, content: String) -> RunEvent {
        RunEvent(
            type: type,
            content: AnyCodable(content),
            tool: nil,
            args: nil,
            output: nil,
            success: nil,
            step_id: nil,
            attempt: nil,
            decision: nil,
            reason: nil,
            error: nil,
            skills: nil
        )
    }

    init(
        type: String,
        content: AnyCodable?,
        tool: String?,
        args: AnyCodable?,
        output: String?,
        success: Bool?,
        step_id: String?,
        attempt: Int?,
        decision: String?,
        reason: String?,
        error: String?,
        skills: [String]?
    ) {
        self.type = type
        self.content = content
        self.tool = tool
        self.args = args
        self.output = output
        self.success = success
        self.step_id = step_id
        self.attempt = attempt
        self.decision = decision
        self.reason = reason
        self.error = error
        self.skills = skills
    }

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case tool
        case args
        case output
        case success
        case step_id
        case attempt
        case decision
        case reason
        case error
        case skills
    }
}

struct ActiveConfig: Decodable {
    let provider: String
    let model: String
}

struct ProviderStatus: Codable, Identifiable {
    var id: String { provider }
    let provider: String
    let display_name: String
    let connected: Bool
    let auth_method: String
    let available_models: [String]
    let default_model: String
}

struct CLIArgSchema: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let required: Bool
    let type: String
}

struct CLIManifest: Codable, Identifiable {
    var id: String { name }
    let name: String
    let kind: String
    let description: String
    let version: String
    let command: String
    let args_schema: [CLIArgSchema]
    let examples: [String]
    let homepage: String?
    let author: String?
}

struct TronhubEntry: Codable, Identifiable {
    var id: String { "\(kind):\(name)" }
    let name: String
    let kind: String
    let description: String
    let source_path: String
    let installed: Bool
    let manifest_json: String?
}

struct SkillEntry: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let path: String
}

struct MemoryNote: Codable, Identifiable {
    let id: String
    var scope: String
    var content: String
    var source: String
    var created_at: String
}

struct GlobalMemory: Codable {
    var user_name_preference: String
    var agent_style_preference: String
    var execution_rules: [String]
    var notes: [MemoryNote]
}

struct ProjectMemory: Codable {
    var project_path: String
    var project_name: String
    var archived: Bool
    var format_rules: [String]
    var task_constraints: [String]
    var glossary: [String: String]
    var long_context: [MemoryNote]
}

struct SkillRetryAttempt: Codable, Identifiable {
    var id: String { "\(attempt)-\(created_at)" }
    let attempt: Int
    let status: String
    let reason: String
    let correction: String
    let input: AnyCodable
    let output: String
    let created_at: String
}

struct SkillRetryTrace: Codable, Identifiable {
    let id: String
    let skill: String
    let status: String
    let attempts: [SkillRetryAttempt]
    let created_at: String
}

struct MemorySnapshot: Decodable {
    let global_memory: GlobalMemory
    let project_memory: ProjectMemory
    let effective_prompt: String
    let skill_retry_traces: [SkillRetryTrace]
}

struct MentionModule: Codable, Identifiable {
    var id: String { "\(kind):\(name):\(injection)" }
    let name: String
    let kind: String
    let injection: String
}

struct MentionItem: Codable, Identifiable {
    let id: String
    let label: String
    let kind: String
    let path: String
    let detail: String
    let installed: Bool
    let modules: [MentionModule]
}

struct MentionSearchResult: Decodable {
    let tools: [MentionItem]
    let files: [MentionItem]
    let cloud_suggestions: [MentionItem]
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

final class RustBridge: @unchecked Sendable {
    static let shared = RustBridge()

    private let lock = NSLock()

    func initialize() throws {
        let response = locked {
            readCString(scriptron_init())
        }
        let decoder = JSONDecoder()
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
        let response = locked {
            request.withCString { pointer in
                readCString(scriptron_call(pointer))
            }
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(RpcEnvelope<T>.self, from: Data(response.utf8))
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw BridgeError.runtime(envelope.error ?? "Unknown Rust error")
    }

    func callVoid(_ method: String, params: [String: Any] = [:]) throws {
        let payload: [String: Any] = [
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let request = String(data: data, encoding: .utf8) ?? "{}"
        let response = locked {
            request.withCString { pointer in
                readCString(scriptron_call(pointer))
            }
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(RpcEnvelope<AnyCodable>.self, from: Data(response.utf8))
        if !envelope.ok {
            throw BridgeError.runtime(envelope.error ?? "Unknown Rust error")
        }
    }

    private func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
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
