#if AGENTBAR_NOTIFICATION_SOUNDS
import XCTest
@testable import AgentBar

final class CESPRegistryServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RegistryServiceMockURLProtocol.reset()
    }

    override func tearDown() {
        RegistryServiceMockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchPacksDecodesRegistryResponse() async throws {
        RegistryServiceMockURLProtocol.responseProvider = { _ in
            (200, Self.registryIndexJSON(packName: "wc3-en"))
        }

        let service = makeService()
        let packs = try await service.fetchPacks()

        XCTAssertEqual(packs.count, 1)
        XCTAssertEqual(packs.first?.name, "wc3-en")
        XCTAssertEqual(RegistryServiceMockURLProtocol.requestCount, 1)
    }

    func testFetchPacksUsesCacheWhenForceRefreshDisabled() async throws {
        RegistryServiceMockURLProtocol.responseProvider = { _ in
            (200, Self.registryIndexJSON(packName: "cached-pack"))
        }

        let service = makeService()
        let first = try await service.fetchPacks()
        let second = try await service.fetchPacks()

        XCTAssertEqual(first.map(\.name), ["cached-pack"])
        XCTAssertEqual(second.map(\.name), ["cached-pack"])
        XCTAssertEqual(RegistryServiceMockURLProtocol.requestCount, 1)
    }

    func testFetchPacksForceRefreshBypassesCache() async throws {
        RegistryServiceMockURLProtocol.responseProvider = { requestNumber in
            if requestNumber == 1 {
                return (200, Self.registryIndexJSON(packName: "old-pack"))
            }
            return (200, Self.registryIndexJSON(packName: "new-pack"))
        }

        let service = makeService()
        let first = try await service.fetchPacks()
        let refreshed = try await service.fetchPacks(forceRefresh: true)

        XCTAssertEqual(first.map(\.name), ["old-pack"])
        XCTAssertEqual(refreshed.map(\.name), ["new-pack"])
        XCTAssertEqual(RegistryServiceMockURLProtocol.requestCount, 2)
    }

    func testFetchPacksThrowsFetchFailedForHTTPError() async {
        RegistryServiceMockURLProtocol.responseProvider = { _ in
            (500, Data())
        }

        let service = makeService()

        do {
            _ = try await service.fetchPacks()
            XCTFail("Expected fetch to fail")
        } catch let error as CESPRegistryError {
            guard case .fetchFailed = error else {
                XCTFail("Expected fetchFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchPacksThrowsDecodingErrorForInvalidJSON() async {
        RegistryServiceMockURLProtocol.responseProvider = { _ in
            (200, Data("{\"packs\":\"invalid\"}".utf8))
        }

        let service = makeService()

        do {
            _ = try await service.fetchPacks()
            XCTFail("Expected decoding to fail")
        } catch is DecodingError {
            // expected
        } catch {
            XCTFail("Expected DecodingError, got \(error)")
        }
    }

    private func makeService() -> CESPRegistryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RegistryServiceMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return CESPRegistryService(session: session)
    }

    private static func registryIndexJSON(packName: String) -> Data {
        Data(
            """
            {
              "packs": [
                {
                  "name": "\(packName)",
                  "display_name": "Pack \(packName)",
                  "source_repo": "peonping/\(packName)",
                  "source_ref": "main",
                  "source_path": "pack"
                }
              ]
            }
            """.utf8
        )
    }
}

private final class RegistryServiceMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) static var requestCount: Int = 0
    nonisolated(unsafe) static var responseProvider: ((Int) -> (statusCode: Int, data: Data))?

    static func reset() {
        lock.lock()
        requestCount = 0
        responseProvider = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let responseTuple: (statusCode: Int, data: Data)
        let requestNumber: Int

        Self.lock.lock()
        Self.requestCount += 1
        requestNumber = Self.requestCount
        responseTuple = Self.responseProvider?(requestNumber) ?? (500, Data())
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseTuple.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseTuple.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
