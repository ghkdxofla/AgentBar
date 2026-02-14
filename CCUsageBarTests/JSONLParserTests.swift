import XCTest
@testable import CCUsageBar

private struct TestRecord: Decodable {
    let type: String?
    let timestamp: String?
    let costUSD: Double?
    let usage: TestUsage?
}

private struct TestUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
}

final class JSONLParserTests: XCTestCase {

    func testParseValidJSONL() {
        let input = """
        {"type":"assistant","timestamp":"2026-02-14T10:00:00Z","usage":{"input_tokens":100,"output_tokens":50},"costUSD":0.01}
        {"type":"user","timestamp":"2026-02-14T10:01:00Z"}
        {"type":"assistant","timestamp":"2026-02-14T10:02:00Z","usage":{"input_tokens":200,"output_tokens":100},"costUSD":0.02}
        """

        let records = JSONLParser.parse(input, as: TestRecord.self)

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].usage?.input_tokens, 100)
        XCTAssertEqual(records[0].usage?.output_tokens, 50)
        XCTAssertEqual(records[0].costUSD, 0.01)
        XCTAssertEqual(records[2].costUSD, 0.02)
    }

    func testParsePartiallyCorruptedJSONL() {
        let input = """
        {"type":"assistant","usage":{"input_tokens":100}}
        {invalid json line}
        {"type":"assistant","usage":{"input_tokens":200}}
        """

        let records = JSONLParser.parse(input, as: TestRecord.self)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].usage?.input_tokens, 100)
        XCTAssertEqual(records[1].usage?.input_tokens, 200)
    }

    func testParseEmptyString() {
        let records = JSONLParser.parse("", as: TestRecord.self)
        XCTAssertTrue(records.isEmpty)
    }

    func testParseFileStreaming() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("test.jsonl")
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("""
            {"type":"assistant","timestamp":"2026-02-14T10:00:00Z","usage":{"input_tokens":\(i * 10),"output_tokens":\(i * 5)}}
            """)
        }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let records = try JSONLParser.parseFile(file, as: TestRecord.self)
        XCTAssertEqual(records.count, 100)
        XCTAssertEqual(records[0].usage?.input_tokens, 0)
        XCTAssertEqual(records[99].usage?.input_tokens, 990)
    }

    func testParseFileNonexistent() throws {
        let records = try JSONLParser.parseFile(
            URL(fileURLWithPath: "/nonexistent/file.jsonl"),
            as: TestRecord.self
        )
        XCTAssertTrue(records.isEmpty)
    }
}
