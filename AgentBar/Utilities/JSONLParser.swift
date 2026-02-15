import Foundation

enum JSONLParser {
    /// Parse a JSONL string, skipping lines that fail to decode.
    static func parse<T: Decodable>(_ content: String, as type: T.Type) -> [T] {
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                guard let data = trimmed.data(using: .utf8) else { return nil }
                return try? decoder.decode(T.self, from: data)
            }
    }

    /// Stream-parse a JSONL file line by line without loading entire file into memory.
    static func parseFile<T: Decodable>(_ url: URL, as type: T.Type) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            return []
        }
        defer { handle.closeFile() }

        let decoder = JSONDecoder()
        var results: [T] = []
        var buffer = Data()

        let newline = UInt8(ascii: "\n")
        let chunkSize = 64 * 1024 // 64KB chunks

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            for byte in chunk {
                if byte == newline {
                    if !buffer.isEmpty {
                        if let record = try? decoder.decode(T.self, from: buffer) {
                            results.append(record)
                        }
                        buffer.removeAll(keepingCapacity: true)
                    }
                } else {
                    buffer.append(byte)
                }
            }
        }

        // Handle last line without trailing newline
        if !buffer.isEmpty {
            if let record = try? decoder.decode(T.self, from: buffer) {
                results.append(record)
            }
        }

        return results
    }
}
