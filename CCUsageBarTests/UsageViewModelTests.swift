import XCTest
@testable import CCUsageBar

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

    func testProviderFailureReturnsZeroUsage() async {
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

        // Both show: successful provider + zero-usage fallback for failed provider
        XCTAssertEqual(vm.usageData.count, 2)
        let codexData = vm.usageData.first { $0.service == .codex }
        XCTAssertNotNil(codexData)
        XCTAssertEqual(codexData!.fiveHourUsage.used, 0)
    }

    func testAllFailuresStillShowBars() async {
        let failProvider = MockUsageProvider(
            serviceType: .claude,
            result: .failure(APIError.noData)
        )

        let vm = UsageViewModel(providers: [failProvider])
        await vm.fetchAllUsage()

        // Failed provider still returns a zero-usage entry
        XCTAssertEqual(vm.usageData.count, 1)
        XCTAssertEqual(vm.usageData.first?.fiveHourUsage.used, 0)
        XCTAssertNil(vm.lastError)
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
        let gemini = MockUsageProvider(serviceType: .gemini, result: .success(UsageData.mock(service: .gemini)))
        let claude = MockUsageProvider(serviceType: .claude, result: .success(UsageData.mock(service: .claude)))
        let codex = MockUsageProvider(serviceType: .codex, result: .success(UsageData.mock(service: .codex)))

        let vm = UsageViewModel(providers: [zai, gemini, claude, codex])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 4)
        XCTAssertEqual(vm.usageData[0].service, .claude)
        XCTAssertEqual(vm.usageData[1].service, .codex)
        XCTAssertEqual(vm.usageData[2].service, .gemini)
        XCTAssertEqual(vm.usageData[3].service, .zai)
    }

}
