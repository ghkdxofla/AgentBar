#if AGENTBAR_NOTIFICATION_SOUNDS
import XCTest
@testable import AgentBar

final class CESPRegistryPackTests: XCTestCase {

    func testDecodesRegistryIndex() throws {
        let json = """
        {
          "packs": [
            {
              "name": "warcraft3",
              "display_name": "Warcraft III",
              "description": "Classic Warcraft III peon sounds",
              "source_repo": "peonping/warcraft3-sounds",
              "source_ref": "v1.0.0",
              "source_path": "pack",
              "sound_count": 12,
              "total_size_bytes": 524288,
              "language": "en",
              "trust_tier": "official",
              "tags": ["game", "warcraft"]
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let index = try JSONDecoder().decode(CESPRegistryIndex.self, from: data)

        XCTAssertEqual(index.packs.count, 1)
        let pack = index.packs[0]
        XCTAssertEqual(pack.name, "warcraft3")
        XCTAssertEqual(pack.display_name, "Warcraft III")
        XCTAssertEqual(pack.description, "Classic Warcraft III peon sounds")
        XCTAssertEqual(pack.source_repo, "peonping/warcraft3-sounds")
        XCTAssertEqual(pack.source_ref, "v1.0.0")
        XCTAssertEqual(pack.source_path, "pack")
        XCTAssertEqual(pack.sound_count, 12)
        XCTAssertEqual(pack.total_size_bytes, 524288)
        XCTAssertEqual(pack.trust_tier, "official")
        XCTAssertEqual(pack.tags, ["game", "warcraft"])
    }

    func testFormattedSizeBytes() {
        let pack = makeTestPack(totalSizeBytes: 512)
        XCTAssertEqual(pack.formattedSize, "512 B")
    }

    func testFormattedSizeKilobytes() {
        let pack = makeTestPack(totalSizeBytes: 2048)
        XCTAssertEqual(pack.formattedSize, "2.0 KB")
    }

    func testFormattedSizeMegabytes() {
        let pack = makeTestPack(totalSizeBytes: 1_572_864) // 1.5 MB
        XCTAssertEqual(pack.formattedSize, "1.5 MB")
    }

    func testFormattedSizeNil() {
        let pack = makeTestPack(totalSizeBytes: nil)
        XCTAssertEqual(pack.formattedSize, "")
    }

    func testManifestURL() {
        let pack = makeTestPack(sourceRepo: "peonping/wc3", sourceRef: "v1.0", sourcePath: "pack")
        XCTAssertEqual(
            pack.manifestURL.absoluteString,
            "https://raw.githubusercontent.com/peonping/wc3/v1.0/pack/openpeon.json"
        )
    }

    func testBaseContentURL() {
        let pack = makeTestPack(sourceRepo: "user/repo", sourceRef: "main", sourcePath: "sounds")
        XCTAssertEqual(
            pack.baseContentURL.absoluteString,
            "https://raw.githubusercontent.com/user/repo/main/sounds"
        )
    }

    func testIdentifiable() {
        let pack = makeTestPack(name: "my-pack")
        XCTAssertEqual(pack.id, "my-pack")
    }

    func testDecodesWithMinimalFields() throws {
        let json = """
        {
          "packs": [
            {
              "name": "minimal",
              "display_name": "Minimal Pack",
              "source_repo": "user/repo",
              "source_ref": "main",
              "source_path": "."
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let index = try JSONDecoder().decode(CESPRegistryIndex.self, from: data)
        XCTAssertEqual(index.packs.count, 1)
        XCTAssertNil(index.packs[0].sound_count)
        XCTAssertNil(index.packs[0].total_size_bytes)
        XCTAssertNil(index.packs[0].tags)
    }

    // MARK: - Helpers

    private func makeTestPack(
        name: String = "test",
        sourceRepo: String = "user/repo",
        sourceRef: String = "main",
        sourcePath: String = "pack",
        totalSizeBytes: Int? = nil
    ) -> CESPRegistryPack {
        CESPRegistryPack(
            name: name,
            display_name: "Test Pack",
            description: nil,
            source_repo: sourceRepo,
            source_ref: sourceRef,
            source_path: sourcePath,
            sound_count: nil,
            total_size_bytes: totalSizeBytes,
            language: nil,
            trust_tier: nil,
            tags: nil
        )
    }
}
#endif
