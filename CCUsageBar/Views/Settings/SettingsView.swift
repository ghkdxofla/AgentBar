import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let limitsChanged = Notification.Name("CCUsageBarLimitsChanged")
}

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    @AppStorage("claudeEnabled") private var claudeEnabled = true
    @AppStorage("claudePlan") private var claudePlan: String = ClaudePlan.max5x.rawValue
    @AppStorage("claudeFiveHourLimit") private var claudeFiveHourLimit: Double = 2_500_000
    @AppStorage("claudeWeeklyLimit") private var claudeWeeklyLimit: Double = 50_000_000

    @AppStorage("codexEnabled") private var codexEnabled = true
    @AppStorage("codexPlan") private var codexPlan: String = CodexPlan.pro.rawValue
    @AppStorage("codexFiveHourLimit") private var codexFiveHourLimit: Double = 10_000_000
    @AppStorage("codexWeeklyLimit") private var codexWeeklyLimit: Double = 100_000_000

    @AppStorage("zaiEnabled") private var zaiEnabled = true

    @State private var openaiAPIKey: String = ""
    @State private var zaiAPIKey: String = ""
    @State private var showSavedAlert = false

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

                Picker("Plan", selection: $claudePlan) {
                    ForEach(ClaudePlan.allCases, id: \.rawValue) { plan in
                        Text(plan.rawValue).tag(plan.rawValue)
                    }
                }
                .onChange(of: claudePlan) { newValue in
                    if let plan = ClaudePlan(rawValue: newValue), plan != .custom {
                        claudeFiveHourLimit = plan.fiveHourTokenLimit
                        claudeWeeklyLimit = plan.weeklyTokenLimit
                    }
                    NotificationCenter.default.post(name: .limitsChanged, object: nil)
                }

                HStack {
                    Text("5h token limit:")
                    TextField("", value: $claudeFiveHourLimit, format: .number)
                        .frame(width: 120)
                        .disabled(claudePlan != ClaudePlan.custom.rawValue)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: claudeFiveHourLimit) { _ in
                    if claudePlan == ClaudePlan.custom.rawValue {
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                }

                HStack {
                    Text("Weekly token limit:")
                    TextField("", value: $claudeWeeklyLimit, format: .number)
                        .frame(width: 120)
                        .disabled(claudePlan != ClaudePlan.custom.rawValue)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: claudeWeeklyLimit) { _ in
                    if claudePlan == ClaudePlan.custom.rawValue {
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                }
            }

            // OpenAI Codex
            Section("OpenAI Codex") {
                Toggle("Enabled", isOn: $codexEnabled)
                HStack {
                    Text("API Key:")
                    SecureField("sk-...", text: $openaiAPIKey)
                        .frame(width: 200)
                    Button("Save") {
                        saveAPIKey(openaiAPIKey, account: ServiceType.codex.keychainAccount)
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
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
            }

            // Z.ai
            Section("Z.ai Coding Plan") {
                Toggle("Enabled", isOn: $zaiEnabled)
                HStack {
                    Text("API Key:")
                    SecureField("API key", text: $zaiAPIKey)
                        .frame(width: 200)
                    Button("Save") {
                        saveAPIKey(zaiAPIKey, account: ServiceType.zai.keychainAccount)
                        NotificationCenter.default.post(name: .limitsChanged, object: nil)
                    }
                }
                Text("Limits are fetched automatically from Z.ai API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 580)
        .onAppear {
            loadAPIKeys()
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func saveAPIKey(_ key: String, account: String) {
        guard !key.isEmpty else { return }
        try? KeychainManager.save(key: key, account: account)
        showSavedAlert = true
    }

    private func loadAPIKeys() {
        if let key = KeychainManager.load(account: ServiceType.codex.keychainAccount) {
            openaiAPIKey = String(repeating: "*", count: min(key.count, 12))
        }
        if let key = KeychainManager.load(account: ServiceType.zai.keychainAccount) {
            zaiAPIKey = String(repeating: "*", count: min(key.count, 12))
        }
    }
}
