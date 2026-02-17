#if AGENTBAR_NOTIFICATION_SOUNDS
import Foundation

struct CESPRegistryIndex: Decodable, Sendable {
    let packs: [CESPRegistryPack]
}

struct CESPRegistryPack: Decodable, Sendable, Identifiable {
    let name: String
    let display_name: String
    let description: String?
    let source_repo: String
    let source_ref: String
    let source_path: String
    let sound_count: Int?
    let total_size_bytes: Int?
    let language: String?
    let trust_tier: String?
    let tags: [String]?

    var id: String { name }

    var formattedSize: String {
        guard let bytes = total_size_bytes, bytes > 0 else { return "" }
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        }
    }

    var baseContentURL: URL {
        URL(string: "https://raw.githubusercontent.com/\(source_repo)/\(source_ref)/\(source_path)")!
    }

    var manifestURL: URL {
        baseContentURL.appendingPathComponent("openpeon.json")
    }
}
#endif
