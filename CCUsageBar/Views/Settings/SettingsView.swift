import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let limitsChanged = Notification.Name("CCUsageBarLimitsChanged")
}

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    @AppStorage("claudeEnabled") private var claudeEnabled = true

    @AppStorage("codexEnabled") private var codexEnabled = true
    @AppStorage("codexPlan") private var codexPlan: String = CodexPlan.pro.rawValue
    @AppStorage("codexFiveHourLimit") private var codexFiveHourLimit: Double = 10_000_000
    @AppStorage("codexWeeklyLimit") private var codexWeeklyLimit: Double = 100_000_000

    @AppStorage("geminiEnabled") private var geminiEnabled = true
    @AppStorage("geminiDailyLimit") private var geminiDailyLimit: Double = 1_000

    @AppStorage("copilotEnabled") private var copilotEnabled = true

    @AppStorage("cursorEnabled") private var cursorEnabled = true
    @AppStorage("cursorPlan") private var cursorPlan: String = CursorPlan.pro.rawValue
    @AppStorage("cursorMonthlyLimit") private var cursorMonthlyLimit: Double = 500

    @AppStorage("zaiEnabled") private var zaiEnabled = true

    @State private var copilotPAT: String = ""
    @State private var hasSavedCopilotPAT = false
    @State private var zaiAPIKey: String = ""
    @State private var hasSavedZaiAPIKey = false
    @State private var activeTokenSaveAlert: TokenSaveAlert?
    private let keychainSaveAction: @Sendable (String, String) throws -> Void

    init(
        keychainSaveAction: @escaping @Sendable (String, String) throws -> Void = { key, account in
            try KeychainManager.save(key: key, account: account)
        }
    ) {
        self.keychainSaveAction = keychainSaveAction
    }

    var body: some View {
        Form {
            // General
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        try? LoginItemManager.setEnabled(newValue)
                    }

                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("30s").tag(30.0)
                    Text("60s").tag(60.0)
                    Text("120s").tag(120.0)
                    Text("300s").tag(300.0)
                }
            }

            // Claude Code
            Section("Claude Code") {
                Toggle("Enabled", isOn: $claudeEnabled)
                    .onChange(of: claudeEnabled) { _ in
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                Text("Usage is fetched from Anthropic OAuth API using Claude Code credentials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // OpenAI Codex
            Section("OpenAI Codex") {
                Toggle("Enabled", isOn: $codexEnabled)
                    .onChange(of: codexEnabled) { _ in
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }

                Picker("Plan", selection: $codexPlan) {
                    ForEach(CodexPlan.allCases, id: \.rawValue) { plan in
                        Text(plan.rawValue).tag(plan.rawValue)
                    }
                }
                .onChange(of: codexPlan) { newValue in
                    if let plan = CodexPlan(rawValue: newValue), plan != .custom {
                        codexFiveHourLimit = plan.fiveHourTokenLimit
                        codexWeeklyLimit = plan.weeklyTokenLimit
                    }
                    NotificationCenter.default.post(name: .limitsChanged, object: nil)
                }

                HStack {
                    Text("5h token limit:")
                    TextField("", value: $codexFiveHourLimit, format: .number)
                        .frame(width: 120)
                        .disabled(codexPlan != CodexPlan.custom.rawValue)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: codexFiveHourLimit) { _ in
                    if codexPlan == CodexPlan.custom.rawValue {
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                }

                HStack {
                    Text("Weekly token limit:")
                    TextField("", value: $codexWeeklyLimit, format: .number)
                        .frame(width: 120)
                        .disabled(codexPlan != CodexPlan.custom.rawValue)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: codexWeeklyLimit) { _ in
                    if codexPlan == CodexPlan.custom.rawValue {
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                }

                Text("Usage is derived from local session logs in ~/.codex/sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Google Gemini
            Section("Google Gemini") {
                Toggle("Enabled", isOn: $geminiEnabled)
                    .onChange(of: geminiEnabled) { _ in
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }

                HStack {
                    Text("Daily request limit:")
                    TextField("", value: $geminiDailyLimit, format: .number)
                        .frame(width: 120)
                    Text("requests")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: geminiDailyLimit) { _ in
                    NotificationCenter.default.post(name: .limitsChanged, object: nil)
                }

                Text("Usage is derived from local Gemini logs in ~/.gemini/tmp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // GitHub Copilot
            Section("GitHub Copilot") {
                Toggle("Enabled", isOn: $copilotEnabled)
                    .onChange(of: copilotEnabled) { _ in
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                Text("Token is auto-read from gh CLI (gh auth token)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Manual PAT (optional fallback)") {
                    if hasSavedCopilotPAT {
                        Text("A manual PAT is already saved in Keychain")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        SecureField("ghp_...", text: $copilotPAT)
                            .frame(width: 200)
                        Button("Save") {
                            if saveCopilotPAT() {
                                NotificationCenter.default.post(name: .limitsChanged, object: nil)
                            }
                        }
                        .disabled(!Self.canSaveToken(copilotPAT))
                    }
                    Text("Only needed if gh CLI is not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            // Cursor
            Section("Cursor") {
                Toggle("Enabled", isOn: $cursorEnabled)
                    .onChange(of: cursorEnabled) { _ in
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }

                Picker("Plan", selection: $cursorPlan) {
                    ForEach(CursorPlan.allCases, id: \.rawValue) { plan in
                        Text(plan.rawValue).tag(plan.rawValue)
                    }
                }
                .onChange(of: cursorPlan) { newValue in
                    if let plan = CursorPlan(rawValue: newValue), plan != .custom {
                        cursorMonthlyLimit = plan.monthlyRequestEstimate
                    }
                    NotificationCenter.default.post(name: .limitsChanged, object: nil)
                }

                HStack {
                    Text("Est. monthly requests:")
                    TextField("", value: $cursorMonthlyLimit, format: .number)
                        .frame(width: 120)
                        .disabled(cursorPlan != CursorPlan.custom.rawValue)
                    Text("requests")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: cursorMonthlyLimit) { _ in
                    if cursorPlan == CursorPlan.custom.rawValue {
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                }

                Text("Credit-based pricing since June 2025. Actual limit varies by model. Token is auto-read from Cursor's local database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Z.ai
            Section("Z.ai Coding Plan") {
                Toggle("Enabled", isOn: $zaiEnabled)
                    .onChange(of: zaiEnabled) { _ in
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                if hasSavedZaiAPIKey {
                    Text("An API key is already saved in Keychain")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("API Key:")
                    SecureField("API key", text: $zaiAPIKey)
                        .frame(width: 200)
                    Button("Save") {
                        let outcome = saveTokenWithUIState(
                            zaiAPIKey,
                            account: ServiceType.zai.keychainAccount,
                            hasSavedToken: hasSavedZaiAPIKey
                        )
                        hasSavedZaiAPIKey = outcome.hasSavedToken
                        zaiAPIKey = outcome.tokenFieldValue
                        if outcome.didSave {
                            NotificationCenter.default.post(name: .limitsChanged, object: nil)
                        }
                    }
                    .disabled(!Self.canSaveToken(zaiAPIKey))
                }
                Text("Limits are fetched automatically from Z.ai API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 800)
        .onAppear {
            migrateLegacyCursorPlanIfNeeded()
            loadAPIKeys()
        }
        .alert(item: $activeTokenSaveAlert) { alert in
            switch alert {
            case .saved:
                return Alert(
                    title: Text("Saved"),
                    dismissButton: .cancel(Text("OK"))
                )
            case .saveFailed(let message):
                return Alert(
                    title: Text("Save Failed"),
                    message: Text(message),
                    dismissButton: .cancel(Text("OK"))
                )
            }
        }
    }

    @discardableResult
    private func saveCopilotPAT() -> Bool {
        let outcome = saveTokenWithUIState(
            copilotPAT,
            account: ServiceType.copilot.keychainAccount,
            hasSavedToken: hasSavedCopilotPAT
        )
        hasSavedCopilotPAT = outcome.hasSavedToken
        copilotPAT = outcome.tokenFieldValue
        return outcome.didSave
    }

    private func saveTokenWithUIState(
        _ token: String,
        account: String,
        hasSavedToken: Bool
    ) -> TokenSaveUIOutcome {
        let outcome = Self.tokenSaveUIOutcome(
            currentToken: token,
            hasSavedToken: hasSavedToken,
            account: account,
            save: keychainSaveAction
        )
        if outcome.showSavedAlert {
            activeTokenSaveAlert = .saved
        } else if outcome.showSaveErrorAlert {
            activeTokenSaveAlert = .saveFailed(outcome.saveErrorMessage)
        } else {
            activeTokenSaveAlert = nil
        }
        return outcome
    }

    private func migrateLegacyCursorPlanIfNeeded() {
        let resolvedPlan = CursorPlan.resolveAndMigrateStoredPlan()
        guard resolvedPlan.rawValue != cursorPlan else { return }

        cursorPlan = resolvedPlan.rawValue
        if resolvedPlan != .custom {
            cursorMonthlyLimit = resolvedPlan.monthlyRequestEstimate
        }
    }

    private func loadAPIKeys() {
        hasSavedCopilotPAT = KeychainManager.load(account: ServiceType.copilot.keychainAccount) != nil
        hasSavedZaiAPIKey = KeychainManager.load(account: ServiceType.zai.keychainAccount) != nil
        copilotPAT = ""
        zaiAPIKey = ""
    }

    struct CopilotPATSaveOutcome: Equatable {
        let didSave: Bool
        let hasSavedCopilotPAT: Bool
        let copilotPAT: String
    }

    struct TokenSaveUIOutcome: Equatable {
        let didSave: Bool
        let hasSavedToken: Bool
        let tokenFieldValue: String
        let showSavedAlert: Bool
        let showSaveErrorAlert: Bool
        let saveErrorMessage: String
    }

    enum TokenSaveAlert: Identifiable {
        case saved
        case saveFailed(String)

        var id: String {
            switch self {
            case .saved:
                return "saved"
            case .saveFailed(let message):
                return "saveFailed:\(message)"
            }
        }
    }

    static func copilotPATSaveOutcome(
        currentPAT: String,
        hasSavedCopilotPAT: Bool,
        save: (String) -> Bool
    ) -> CopilotPATSaveOutcome {
        let outcome = tokenSaveUIOutcome(
            currentToken: currentPAT,
            hasSavedToken: hasSavedCopilotPAT,
            account: ServiceType.copilot.keychainAccount
        ) { token, _ in
            if save(token) {
                return
            }
            throw SaveOutcomeError.didNotSave
        }
        return CopilotPATSaveOutcome(
            didSave: outcome.didSave,
            hasSavedCopilotPAT: outcome.hasSavedToken,
            copilotPAT: outcome.tokenFieldValue
        )
    }

    enum SaveResult {
        case success
        case failure(String)
    }

    static func saveAPIKeyResult(
        _ key: String,
        account: String,
        save: (String, String) throws -> Void = { key, account in
            try KeychainManager.save(key: key, account: account)
        }
    ) -> SaveResult {
        guard let sanitizedKey = sanitizedTokenForSaving(key) else {
            return .failure("Please enter a valid token before saving.")
        }
        do {
            try save(sanitizedKey, account)
            return .success
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty {
                return .failure("Failed to save token to Keychain.")
            }
            return .failure(message)
        }
    }

    static func tokenSaveUIOutcome(
        currentToken: String,
        hasSavedToken: Bool,
        account: String,
        save: (String, String) throws -> Void = { key, account in
            try KeychainManager.save(key: key, account: account)
        }
    ) -> TokenSaveUIOutcome {
        switch saveAPIKeyResult(currentToken, account: account, save: save) {
        case .success:
            return TokenSaveUIOutcome(
                didSave: true,
                hasSavedToken: true,
                tokenFieldValue: "",
                showSavedAlert: true,
                showSaveErrorAlert: false,
                saveErrorMessage: ""
            )
        case .failure(let message):
            return TokenSaveUIOutcome(
                didSave: false,
                hasSavedToken: hasSavedToken,
                tokenFieldValue: currentToken,
                showSavedAlert: false,
                showSaveErrorAlert: true,
                saveErrorMessage: message
            )
        }
    }

    static func sanitizedTokenForSaving(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSaveToken(trimmed) else { return nil }
        return trimmed
    }

    static func canSaveToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.allSatisfy { $0 == "*" }
    }
}

private enum SaveOutcomeError: Error {
    case didNotSave
}
