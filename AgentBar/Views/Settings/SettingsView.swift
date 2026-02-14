import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    @AppStorage("claudeEnabled") private var claudeEnabled = true
    @AppStorage("claudeFiveHourLimit") private var claudeFiveHourLimit: Double = 500_000
    @AppStorage("claudeWeeklyLimit") private var claudeWeeklyLimit: Double = 10_000_000

    @AppStorage("codexEnabled") private var codexEnabled = true
    @AppStorage("codexFiveHourLimit") private var codexFiveHourLimit: Double = 5.0
    @AppStorage("codexWeeklyLimit") private var codexWeeklyLimit: Double = 50.0

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
                HStack {
                    Text("5h token limit:")
                    TextField("", value: $claudeFiveHourLimit, format: .number)
                        .frame(width: 120)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Weekly token limit:")
                    TextField("", value: $claudeWeeklyLimit, format: .number)
                        .frame(width: 120)
                    Text("tokens")
                        .foregroundStyle(.secondary)
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
                    }
                }
                HStack {
                    Text("5h cost limit:")
                    TextField("", value: $codexFiveHourLimit, format: .currency(code: "USD"))
                        .frame(width: 100)
                }
                HStack {
                    Text("Weekly cost limit:")
                    TextField("", value: $codexWeeklyLimit, format: .currency(code: "USD"))
                        .frame(width: 100)
                }
            }

            // Z.ai
            Section("Z.ai GLM") {
                Toggle("Enabled", isOn: $zaiEnabled)
                HStack {
                    Text("API Key:")
                    SecureField("API key", text: $zaiAPIKey)
                        .frame(width: 200)
                    Button("Save") {
                        saveAPIKey(zaiAPIKey, account: ServiceType.zai.keychainAccount)
                    }
                }
                Text("Limits are fetched automatically from Z.ai API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 520)
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
