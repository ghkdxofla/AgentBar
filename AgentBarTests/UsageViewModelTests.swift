import XCTest
@testable import AgentBar

@MainActor
final class UsageViewModelTests: XCTestCase {

    func testFetchAllUsageWithMultipleProviders() async {
        let mockClaude = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )
        let mockCodex = MockUsageProvider(
            serviceType: .codex,
            result: .success(UsageData.mock(service: .codex))
        )

        let vm = UsageViewModel(providers: [mockClaude, mockCodex])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 2)
        XCTAssertEqual(vm.usageData[0].service, .claude)
        XCTAssertEqual(vm.usageData[1].service, .codex)
    }

    func testProviderFailureDoesNotAffectOthers() async {
        let failProvider = MockUsageProvider(
            serviceType: .codex,
            result: .failure(APIError.unauthorized)
        )
        let successProvider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )

        let vm = UsageViewModel(providers: [failProvider, successProvider])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 1)
        XCTAssertEqual(vm.usageData.first?.service, .claude)
    }

    func testEmptyResultsSetsError() async {
        let failProvider = MockUsageProvider(
            serviceType: .claude,
            result: .failure(APIError.noData)
        )

        let vm = UsageViewModel(providers: [failProvider])
        await vm.fetchAllUsage()

        XCTAssertTrue(vm.usageData.isEmpty)
        XCTAssertNotNil(vm.lastError)
    }

    func testSuccessfulResultsClearsError() async {
        let provider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )

        let vm = UsageViewModel(providers: [provider])
        vm.lastError = "previous error"
        await vm.fetchAllUsage()

        XCTAssertNil(vm.lastError)
    }

    func testServiceOrderIsMaintained() async {
        // Provide in reverse order
        let zai = MockUsageProvider(serviceType: .zai, result: .success(UsageData.mock(service: .zai)))
        let claude = MockUsageProvider(serviceType: .claude, result: .success(UsageData.mock(service: .claude)))
        let codex = MockUsageProvider(serviceType: .codex, result: .success(UsageData.mock(service: .codex)))

        let vm = UsageViewModel(providers: [zai, claude, codex])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 3)
        XCTAssertEqual(vm.usageData[0].service, .claude)
        XCTAssertEqual(vm.usageData[1].service, .codex)
        XCTAssertEqual(vm.usageData[2].service, .zai)
    }
}
