#if AGENTBAR_NOTIFICATION_SOUNDS
import Foundation

actor CESPRegistryService {
    static let shared = CESPRegistryService()

    private static let registryURL = URL(string: "https://peonping.github.io/registry/index.json")!
    private static let cacheTTL: TimeInterval = 3600 // 1 hour

    private var cachedPacks: [CESPRegistryPack]?
    private var cacheTimestamp: Date?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPacks(forceRefresh: Bool = false) async throws -> [CESPRegistryPack] {
        if !forceRefresh, let cached = cachedPacks, let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < Self.cacheTTL {
            return cached
        }

        let (data, response) = try await session.data(from: Self.registryURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CESPRegistryError.fetchFailed
        }

        let index = try JSONDecoder().decode(CESPRegistryIndex.self, from: data)
        cachedPacks = index.packs
        cacheTimestamp = Date()
        return index.packs
    }
}

enum CESPRegistryError: Error, LocalizedError {
    case fetchFailed
    case downloadFailed(String)
    case manifestParseFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch sound pack registry."
        case .downloadFailed(let detail):
            return "Download failed: \(detail)"
        case .manifestParseFailed:
            return "Failed to parse sound pack manifest."
        }
    }
}
#endif
