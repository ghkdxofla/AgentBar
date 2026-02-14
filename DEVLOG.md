# CCUsageBar Development Log (formerly AgentBar)

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

## Iteration 13: Fix Claude token overcounting + Z.ai refresh
- **Claude token overcounting fix**: `cache_read_input_tokens` was being included in totals — these are free and not rate-limited. Changed `totalTokens` to `rateLimitTokens` (input + output only). Reduced reported usage from ~1.38B to ~2.4M across all projects
- **Streaming deduplication**: Claude Code logs multiple records per API call during streaming (same message ID). Added `deduplicateByMessageID()` — keeps only the last record per ID. 5169 duplicate records were being double-counted
- **Z.ai refresh on key save**: API key save in settings now posts `.limitsChanged` notification, triggering immediate provider rebuild + fetch instead of waiting for the next 60s timer tick
- Tests updated: added `testExcludesCacheReadTokens`, `testDeduplicatesStreamingRecords`, `testIgnoresNonAssistantRecords`
- All 35 tests passing

## Iteration 14: Fix Z.ai API response model mismatch
- **Root cause**: `ZaiQuotaResponse` model didn't match actual API response structure
  - Response wraps in `{code, msg, data, success}` — model only expected `{data}`
  - `ZaiLimit` fields: `used`/`total` don't exist — actual fields are `usage` (capacity), `currentValue` (used), `remaining`
  - `TOKENS_LIMIT` has no usage data; `TIME_LIMIT` is the active rate limit (requests)
  - `ZaiUsageDetail` used `tokens`/`calls` — actual fields are `modelCode`/`usage`
- **Weekly API fix**: expected epoch ms timestamps, actual format is `yyyy-MM-dd HH:mm:ss`
  - Response has `totalUsage.totalModelCallCount` / `totalTokensUsage`
- Rewrote all Z.ai Decodable models to match verified API responses
- Z.ai now displays request-based usage (TIME_LIMIT) with proper reset times
- All 35 tests passing

## Iteration 15: Menu bar visibility + reset time display
- **Menu bar labels**: Added short service names (CC/CX/Z) before each bar in service color
- **Bar background**: Changed from gray 20% opacity to service-colored 15% opacity — bars are visible even at 0% usage
- **Minimum bar width**: Usage bars have 2px minimum when > 0% so tiny usage is still visible
- **Reset time in popover**: Each metric row (5h/7d) now shows remaining time until window reset inline (e.g. "4h 23m" with arrow icon), supports d/h/m formatting
- Removed standalone reset text block from ServiceDetailRow, integrated into MetricRow
- `ServiceType.shortName` added: CC (Claude Code), CX (Codex), Z (Z.ai)
- Status bar width increased from 70 to 90px to accommodate labels

## Iteration 16: Reset time fix + rename + Z.ai single window
- **Claude reset time fix**: Rolling window reset computed from earliest record timestamp in window (`earliestTimestamp + windowDuration`) instead of broken `nextResetTime(from: windowStart)` which always equaled `now`
- **Z.ai single rate window**: Z.ai only has one quota (monthly TIME_LIMIT), removed weekly API fetch and made `UsageData.weeklyUsage` optional. Z.ai now shows single "Quota" row instead of two rows
- **Z.ai label fix**: `fiveHourLabel` returns "Quota" for Z.ai, "5h" for others; `weeklyLabel` returns "7d"
- **Rename "Z.ai GLM" → "Z.ai Coding Plan"**
- **Rename AgentBar → CCUsageBar**: project name, directories (`CCUsageBar/`, `CCUsageBarTests/`), bundle ID (`com.ccusagebar.app`), entitlements, `@main` struct, all imports, UI text, notification names
- Removed unused `ZaiModelUsageResponse`, `ZaiModelUsageData`, `ZaiTotalUsage` models and `fetchWeeklyUsage()` method
- Views updated to handle optional `weeklyUsage` (DetailPopoverView, StackedBarView, MiniBarView)
- All 35 tests passing

## Iteration 17: Cost-based Claude usage + Z.ai label
- **Claude usage: cost-based calculation**: Raw token counting didn't match dashboard. Reverse-engineered the formula by comparing with dashboard values (5h=19%, 7d=45%):
  - `cost = input×$15/M + output×$75/M + cache_creation×$18.75/M + cache_read×$1.50/M` (model-specific pricing)
  - `ClaudeModelPricing` struct with Opus/Sonnet/Haiku pricing, selected via `model` field in JSONL records
  - Budgets: Max 5x = $103/5h, $1,133/7d; Max 20x = $412/5h, $4,532/7d (11:1 window ratio)
  - Matches dashboard: `floor($20.53/$103×100)=19%`, `floor($511/$1133×100)=45%`
- **Settings**: Claude limits changed from token fields to dollar budgets (`claudeFiveHourBudget`/`claudeWeeklyBudget`)
- **Z.ai label**: Shortened "Quota" to "Qt" to prevent line wrapping
- Tests: added `testCostIncludesAllTokenTypes`, `testModelSpecificPricing`; updated all assertions to dollar values
- All 36 tests passing

## Iteration 18: Switch CC to ccusage-compatible token formula
- **Problem**: Cost-based formula from Iteration 17 couldn't reliably match the CC dashboard — Anthropic uses a proprietary server-side formula. Researched open-source alternatives (ccusage, tokscale) and confirmed no project can exactly replicate dashboard percentages.
- **Solution**: Adopted ccusage-compatible approach — sum all 4 token types (`input + output + cache_creation + cache_read`) with user-configurable token limits
- **ClaudeUsageProvider**: Removed `ClaudeModelPricing` and cost calculation entirely. Switched back to `fiveHourTokenLimit`/`weeklyTokenLimit` (defaults: 45M/500M). Uses `.tokens` unit instead of `.dollars`
- **SubscriptionPlan**: Changed `ClaudePlan` from dollar budgets (`fiveHourBudget`/`weeklyBudget`) to token limits (`fiveHourTokenLimit`/`weeklyTokenLimit`). Max 5x: 45M/500M, Max 20x: 180M/2B
- **SettingsView**: Claude fields changed from "5h budget:"/"USD" to "5h token limit:"/"tokens". AppStorage keys changed from `claudeFiveHourBudget`/`claudeWeeklyBudget` to `claudeFiveHourLimit`/`claudeWeeklyLimit`
- **UsageViewModel**: Updated to read new AppStorage keys and pass `fiveHourTokenLimit`/`weeklyTokenLimit` to ClaudeUsageProvider
- **Tests**: Rewritten for token-based assertions. Renamed `testCostIncludesAllTokenTypes` → `testSumsAllTokenTypes`. Removed `testModelSpecificPricing` (no longer applicable)
- All 35 tests passing

## Iteration 19: Claude 5h reset alignment with dashboard
- **Claude 5h reset by session start**: `ClaudeUsageProvider` now uses `sessionId` start timestamps from local JSONL logs and computes reset with `DateUtils.nextResetAligned(start, 5h, now)` instead of `earliest assistant in last 5h + 5h`.
- **Why**: In long-running sessions, there can be idle gaps inside a 5h block. Rolling `earliest-in-window` overestimates remaining time; session-based alignment matches dashboard behavior more closely.
- **Fallback behavior**: If `sessionId` metadata is missing, provider falls back to previous rolling-window reset (`earliest + 5h`).
- **ISO8601 parser hardening**: `DateUtils.parseISO8601` now supports microsecond timestamps (e.g. `2025-06-05T17:12:37.153082Z`) used in Claude local metadata.
- **Tests**:
  - Added `DateUtilsTests.testNextResetAlignedUsesAnchorAndWindow`
  - Added `DateUtilsTests.testParseISO8601WithMicroseconds`
  - Added `ClaudeUsageProviderTests.testUsesSessionStartForFiveHourReset`

## Iteration 20: Switch CC to Anthropic OAuth Usage API
- **Problem**: Local JSONL token counting could never match the CC dashboard — Anthropic uses a proprietary server-side formula based on compute cost, not raw token counts. Token type weightings (cache_read ≠ input ≠ output), model-specific multipliers (Opus vs Sonnet), and unpublished plan limits made local estimation fundamentally inaccurate for both usage percentage and reset times.
- **Solution**: Call `GET https://api.anthropic.com/api/oauth/usage` with the OAuth bearer token stored in macOS Keychain by Claude Code CLI. This returns the exact `utilization` percentage (0-100) and `resets_at` ISO 8601 timestamp for both 5-hour and 7-day windows — identical to what the CC dashboard and `/usage` command display.
- **ClaudeUsageProvider rewrite**: Removed all local JSONL parsing, session scanning, token counting, and deduplication logic. Now reads OAuth token from Keychain (`"Claude Code-credentials"` service), calls the API, and maps response directly to `UsageData` with `.percent` unit.
- **Removed `ClaudePlan`**: Token-based plan limits (Max 5x: 45M/500M, Max 20x: 180M/2B) are no longer needed since the API returns server-calculated percentages. `SubscriptionPlan.swift` now only contains `CodexPlan`.
- **SettingsView simplified**: Removed Claude plan picker and token limit fields. Claude section now shows only an enable toggle and a note about OAuth API source.
- **UsageViewModel simplified**: Removed Claude plan/limit reading from UserDefaults. Provider is created with no configuration parameters.
- **New `UsageUnit.percent`**: Added to support direct percentage display. `MetricRow` shows "19%" instead of "19.0M / 45.0M tokens" for percent-based metrics.
- **Tests rewritten**: 8 new API-based tests using `MockURLProtocol` for URLSession stubbing: API response parsing, reset time parsing, percentage calculation, null window handling, 401 error handling, missing credentials, header verification, extra field tolerance. `JSONLParserTests` updated to use local test struct instead of removed `ClaudeMessageRecord`.
- All 41 tests passing
