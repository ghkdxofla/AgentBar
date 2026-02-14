# AgentBar Development Log

## Iteration 1: Project Scaffolding + Build Verification
- Created `project.yml` for xcodegen (macOS 13.0, LSUIElement, entitlements)
- Set up `AgentBar/Info.plist` with LSUIElement=true
- Set up `AgentBar/AgentBar.entitlements` with network.client and file read permissions
- Created minimal `AgentBarApp.swift` (@main entry point) and `AppDelegate.swift`
- Created directory structure: Models, ViewModels, Views, Services, Networking, Infrastructure, Utilities
- Added `.gitignore` for Xcode/Swift
- `xcodegen generate` + `xcodebuild build` passes successfully

## Iteration 2: Core Models + Utilities
- `ServiceType` enum with dark/light color extensions per DESIGN.md color palette
- `UsageData`, `UsageMetric`, `UsageUnit` models (all `Sendable`)
- `DateUtils` with 5-hour/weekly window detection and ISO8601 parsing
- `JSONLParser` with in-memory and streaming file parsers (skips corrupt lines)
- `APIError` enum covering all error scenarios
- Note: Used inline `ISO8601DateFormatter` instances instead of shared statics due to Swift 6 Sendable requirements

## Iteration 3: Infrastructure Layer
- `KeychainManager` for secure API key save/load/delete via Security framework
- `LoginItemManager` wrapping `SMAppService` for launch-at-login
- `APIClient` actor with generic `get<T>()` and raw data methods
- `UsageProviderProtocol` — Sendable protocol for all providers

## Iteration 4: Claude Code Provider
- `ClaudeUsageProvider` scans `~/.claude/projects/` subdirectories
- Filters to files modified within 7 days
- Parses JSONL records including sub-agent nested `message.usage`
- Aggregates tokens for 5-hour and weekly windows
- Uses configurable token limits (default 500K / 10M)

## Iteration 5: Z.ai + Codex Providers
- `ZaiUsageProvider` — calls `/api/monitor/usage/quota/limit`, Bearer/Raw auth retry
- `CodexUsageProvider` — OpenAI Usage API for weekly costs + local `~/.codex/sessions/` for 5-hour precision
- Fixed Swift 6 Sendable constraint on generic `fetchWithAuthRetry<T: Decodable & Sendable>`

## Iteration 6: ViewModel + Data Pipeline
- `UsageViewModel` with `@MainActor`, `@Published` properties
- `TaskGroup` parallel fetch from all providers
- `Timer.publish` periodic refresh
- Service order maintained: Claude → Codex → Z.ai

## Iteration 7+8: Menu Bar UI + Popover
- `StackedBarView` — 3-row stacked bar chart in menu bar (64x20px)
- Dynamic bar height: 1 service=12px, 2=8px, 3=5px
- `StatusBarController` — `NSStatusItem` + `NSHostingView` + `Combine` observation
- `PopoverController` — click-to-show `NSPopover` with `DetailPopoverView`
- `DetailPopoverView` — per-service usage details, reset time, mini bar, quit button
- `AppDelegate` wires ViewModel → StatusBarController → monitoring

## Iteration 9: Settings Window
- `SettingsView` with `@AppStorage` for all preferences
- Launch at login toggle, refresh interval picker
- Per-service enable/disable, API key management via Keychain
- Configurable limits for Claude (tokens) and Codex (dollars)
- Z.ai limits auto-fetched from API
- Used macOS 13-compatible `onChange(of:)` API

## Iteration 10: Tests
- 25 unit tests, all passing
- `JSONLParserTests` — valid/corrupt/empty/streaming file parsing
- `DateUtilsTests` — 5h/weekly window boundaries, ISO8601, edge cases
- `UsageViewModelTests` — parallel fetch, error handling, service ordering
- `ClaudeUsageProviderTests` — JSONL parsing, old file filtering, sub-agent tokens, missing dirs
- `MockUsageProvider` + `UsageData.mock()` factory

## Iteration 11: Integration Polish
- Error state indicator in menu bar (warning triangle when no data)
- `StatusBarController` observes both `usageData` and `lastError`
- DEVLOG.md documentation complete

## Iteration 12: Codex Provider Rewrite + Plan Presets
- **CodexUsageProvider full rewrite**: actual `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` structure
  - Recursive directory traversal through date-based subdirectories
  - New data models: `CodexPayload`, `CodexTokenInfo`, `CodexRateLimits`, `CodexRateWindow`
  - Uses `rate_limits.primary/secondary.used_percent` for accurate usage tracking
  - Checks `resets_at` timestamp — zero usage if window already reset
  - Fallback: sums `last_token_usage` tokens when `rate_limits` unavailable
  - `CodexTokenUsage` now includes `cached_input_tokens`, `reasoning_output_tokens`
  - Switched from `UsageUnit.dollars` to `UsageUnit.tokens`
- **SubscriptionPlan.swift** (new): `ClaudePlan` (Max 5x/20x/Custom), `CodexPlan` (Pro/Custom)
- **SettingsView**: plan Picker for Claude & Codex, auto-fill limits, disabled fields unless Custom
- **UsageViewModel**: reads plan/limits from `UserDefaults`, `rebuildProviders()` on `.limitsChanged` notification (debounced 500ms)
- **SettingsWindowController** (new): standalone NSWindow for settings — fixes LSUIElement app issue where `showSettingsWindow:` selector had no responder
- **CodexUsageProviderTests** (new): 8 tests covering directory traversal, rate_limits parsing, reset detection, event filtering, token summing fallback
- All 33 tests passing
