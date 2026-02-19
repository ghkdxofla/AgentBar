# AgentBar Development Log

## Iteration 88: Prevent multiple app instances
- **Single-instance guard**: `AppDelegate.terminateIfAlreadyRunning()` checks `NSRunningApplication` for other processes with the same bundle ID and calls `NSApp.terminate(nil)` if found
- **Test-safe**: Skips the check when `XCTestConfigurationFilePath` environment variable is present (test host shares bundle ID)
- All 277 tests passing

## Iteration 87: Add launch nudge to DMG background
- **Two-step guide**: Updated DMG background from single "Drag to Applications" to numbered steps: "1. Drag AgentBar to Applications" + "2. Open AgentBar to get started"
- **Script refactored**: Extracted `load_font()` and `draw_centered_text()` helpers; step 2 uses slightly smaller font and dimmer alpha for visual hierarchy
- All 277 tests passing

## Iteration 86: Styled DMG installer with create-dmg
- **`scripts/generate-dmg-background.py`**: Python3+Pillow script generating 1200x800 Retina background with slate gradient, chevron arrow, and "Drag to Applications" hint text
- **`docs/assets/dmg-background@2x.png`**: Pre-generated background image committed for reuse across releases
- **`scripts/create-styled-dmg.sh`**: `create-dmg` wrapper with 600x400 window, app icon at (150,200), Applications drop link at (450,200), volume icon, and hidden `.app` extension
- **`scripts/release.sh`**: Replaced bare `hdiutil create` with `create-styled-dmg.sh` call; added `create-dmg` prerequisite check
- All 277 tests passing

## Iteration 85: Post-v0.5 reliability refactor (history + keychain)
- **UsageHistoryStore**: snapshot + append-log(`usage-history.events.jsonl`) 구조로 전환
  - 기록 시 전체 snapshot rewrite 대신 log append
  - load 시 log replay
  - 이벤트 수/파일 크기 임계치 기반 compact(정렬 + snapshot 저장 + log 제거)
  - day/secondary upsert를 index map 기반으로 최적화
- **UsageHistoryDayRecord**: `secondarySampleCount` 필드 추가
  - secondary 평균 계산 분모를 `sampleCount`에서 분리해 희석 오류 방지
  - 구버전 데이터 디코딩 하위호환 유지
- **UsageHistoryViewModel**: `refreshGeneration` + 취소 가능한 단일 `refreshTask` 도입
  - 겹치는 refresh 요청에서 stale 결과 반영 차단
  - secondary 히트맵의 sample count는 `secondarySampleCount` 사용
- **KeychainManager**: load 결과를 `LoadOutcome(value, shouldCache)`로 분리
  - transient Keychain 오류(`errSecInteractionNotAllowed` 등)는 캐시하지 않음
  - 안정 상태(`errSecItemNotFound` 등)만 캐시
- **테스트 추가**
  - `UsageHistoryStoreTests`: secondary 평균 분모 분리 검증
  - `UsageHistoryViewModelTests`: refresh overlap 시 최신 generation 우선 반영 검증
  - `UsageViewModelTests`: Keychain in-process cache의 안정/일시 오류 캐시 정책 검증
- `./scripts/test.sh` 통과

## Iteration 84: Show plan name in zero-usage fallback
- **UsageViewModel.storedPlanName(for:)**: Read plan name from UserDefaults for Claude/Codex/Cursor when fetchUsage() fails, so the plan label still appears next to the service name
- All 273 tests passing

## Iteration 83: Change Codex color from emerald to gray
- **ServiceType darkColor/lightColor**: Codex changed from emerald-500/300 to gray-500/300 (`0.42, 0.45, 0.49` / `0.71, 0.73, 0.76`)
- Test updated: `testCodexDarkColorIsGray500`
- All 273 tests passing

## Iteration 82: Hide non-5h/7d services from Secondary in History tab
- **ServiceType.hasFiveHourSevenDayStructure**: Computed property checking `fiveHourLabel == "5h" && weeklyLabel == "7d"` — only Claude and Codex qualify; Z.ai (MCP) is excluded because MCP monthly is not comparable to 7d cycles
- **UsageHistoryViewModel**: Filter services by `hasFiveHourSevenDayStructure` when `selectedWindow == .secondary`
- **Test updated**: `testNon5h7dServiceIsExcludedFromSecondaryWindow` verifies Z.ai panel is absent in secondary view
- All 273 tests passing

## Iteration 81: Eliminate Keychain permission dialogs via permanent load cache
- **KeychainManager load cache**: Added in-process `[String: CachedValue]` cache to `load(account:)` — first call hits Security framework, all subsequent calls return cached result with zero SecItemCopyMatching calls. Invalidated by `save()`/`delete()` only
- **KeychainManager dataProtection skip**: When `errSecMissingEntitlement` is detected (ad-hoc signing), subsequent calls skip the dataProtection store query entirely
- All 273 tests passing

## Iteration 80: History readability update + daily trend line
- Added per-service `Daily Usage Trend` line chart to the right side of the heatmap using stored daily peak usage values
- Extended day history persistence to keep peak/average `used` values and corresponding unit metadata
- Added top guide text in History tab clarifying tile semantics:
  - Daily Heatmap: `1 tile = 1 day` (weekday ticks on the left)
  - 7d Cycle Consistency: `1 tile = 1 reset cycle`
- Updated cycle section title to explicitly include tile meaning
- Updated plan document to include guide text requirement
- Build and tests pass

## Iteration 79: History tab refinement - all services view and ordering
- Moved `History` tab to the rightmost position in Settings (`Usage` -> `Notifications` -> `History`)
- Reworked `UsageHistoryViewModel` from single-service state to all-service panels
  - added `UsageHistoryServicePanel`
  - computes panel data for every available service in one refresh
  - sorts panels by usage frequency (active days) descending
  - tie-breakers: average daily peak, then stable service order
- Updated `UsageHistoryTabView`
  - removed service dropdown
  - renders all services in one screen (service sections stacked vertically)
  - keeps global window/range controls
  - keeps per-service daily heatmap summary and conditional 7d cycle consistency block
- Updated `UsageHistoryViewModelTests` to new multi-panel API and added frequency ordering test
- Updated `docs/USAGE_HISTORY_IMPLEMENTATION_PLAN.md` to match UI behavior (all services + frequency order + rightmost History tab)
- Build and tests pass

## Iteration 78: Test execution optimization with xctestplan
- **AgentBar.xctestplan (Fast)**: Excludes 3 slow integration test classes (NotifySocketListenerLifecycleTests, HookScriptFallbackTests, AgentNotifyMonitorSocketReceiveTests). Parallel execution enabled. 249 tests, ~15s.
- **AgentBarFull.xctestplan (Full)**: All 267 tests with parallel execution. ~22s. For pre-commit validation.
- **Shared xcscheme**: Created AgentBar.xcscheme linking Fast plan as default, Full plan as alternate.
- **CLAUDE.md updated**: Added fast/full/single-class test commands to Build & Run section.
- **TEST_HOST kept**: Removing TEST_HOST/BUNDLE_LOADER caused linker errors since tests use `@testable import AgentBar`. Kept app-hosted testing; speedup comes from parallelism and slow test exclusion.
- All 267 tests passing

## Iteration 77: Usage History Step 6 - build and runtime handoff
- Rebuilt debug app with `xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet`
- Attempted runtime handoff:
  - terminated existing AgentBar process (`pkill -x AgentBar`)
  - attempted to relaunch app bundle (`open build/Build/Products/Debug/AgentBar.app`)
- In this execution environment, `open` returned LaunchServices error `-600` and direct binary launch exited immediately, so persistent UI runtime verification could not be completed from the agent side
- Delivered build artifact path for local verification: `build/Build/Products/Debug/AgentBar.app`

## Iteration 76: Usage History Step 5 - test coverage
- Added `UsageHistoryStoreTests`:
  - day record peak/average aggregation
  - secondary 5-minute bucket upsert behavior
  - retention pruning (day + sample windows)
  - persistence round-trip
  - corrupt store backup and reset
- Added `UsageHistoryViewModelTests`:
  - heatmap cell count and level mapping
  - daily summary calculation
  - 7d cycle grouping and summary metrics
  - non-7d cycle panel disable behavior
- Updated `UsageViewModelTests`:
  - verifies history records only successful provider results
  - verifies no history write when all providers fail
- Updated `SettingsViewBehaviorTests` with `SettingsTab.history` coverage
- Test suite passes via `./scripts/test.sh`

## Iteration 75: Usage History Step 4 - Settings History tab and UI
- Added `UsageHistoryTabView` in `AgentBar/Views/Settings/UsageHistoryTabView.swift`
- Added `History` tab in `SettingsView` with service/window/range controls
- Implemented `Daily Heatmap` contribution-style grid with tooltip + legend + summary cards
- Implemented conditional `7d Cycle Consistency` section with cycle strip and summary metrics
- Added empty states for no history and insufficient 7d cycle data
- Build passes

## Iteration 74: Usage History Step 3 - History view model and cycle analytics
- Added `UsageHistoryViewModel` in `AgentBar/ViewModels/UsageHistoryViewModel.swift`
- Implemented daily heatmap data generation (`7 x weeks`) and daily summary metrics
- Implemented secondary sample cycle grouping by `resetAt` for 7d consistency analysis
- Added cycle metrics:
  - completion rate
  - days to 80% / 100%
  - high-band hours (`>=80%`, capped segment)
  - current completion streak
- Wired history refresh to `Notification.Name.usageHistoryChanged`
- Build passes

## Iteration 73: Usage History Step 2 - fetch pipeline integration
- `UsageViewModel` now accepts `historyStore: UsageHistoryStoreProtocol` for dependency injection
- `fetchAllUsage()` now tracks provider outcomes as success/failure separately
- Only successful fetch results are recorded to history via `historyStore.record(samples:recordedAt:)`
- Failure fallback rows (`zeroUsageData`) remain visible in UI but are excluded from history recording
- Added `Notification.Name.usageHistoryChanged` broadcast after successful history writes
- Regenerated Xcode project with `xcodegen generate` to include newly added history source files in build
- Build passes

## Iteration 72: Usage History Step 1 - Models and persistent store
- Added `UsageHistory` models in `AgentBar/Models/UsageHistory.swift`:
  - `UsageHistoryDayRecord`
  - `UsageHistorySecondarySample`
  - `UsageHistoryStoreFile` (schema v2)
  - `UsageHistoryWindow`
- Added `UsageHistoryStore` actor in `AgentBar/Infrastructure/UsageHistoryStore.swift` with `UsageHistoryStoreProtocol`
- Implemented persisted history storage at `~/Library/Application Support/AgentBar/usage-history.json`
- Implemented day-level aggregation, secondary sample collection, retention pruning, and atomic JSON writes
- Added corrupt file recovery and legacy schema v1 migration path
- Build passes

## Iteration 71: Fix Claude 7d row disappearing on API failure with valid cache
- **Root cause**: When `fetchUsage()` threw (e.g. OAuth token expired overnight), `UsageViewModel.zeroUsageData()` returned `weeklyUsage: nil`, hiding the 7d row entirely even though cached 7d data was still valid (reset time not yet passed)
- **Cache fallback on API failure**: Added `cachedOrThrow(_:)` to `ClaudeUsageProvider` — on any API error (401, network, etc.), checks UserDefaults cache before throwing. If at least one cached window (5h or 7d) has a valid reset time still in the future, returns cached values instead of throwing
- **Behavior**: 5h resets after sleep → shows 0%. 7d still valid → shows cached %. Both windows expired + API failing → throws as before
- **Tests added**: `testFallsBackToCacheOnAPIFailureWhenSevenDayCacheValid` (401 with valid 7d cache), `testFallsBackToCacheOnMissingCredentials` (nil token with valid 7d cache)
- All 227 tests passing

## Iteration 70: Add app icon to Asset Catalog + update README
- **AppIcon asset catalog**: Created `Assets.xcassets/AppIcon.appiconset` with all macOS icon sizes (16–512@2x), added PBXResourcesBuildPhase to Xcode project so the icon is included in the app bundle
- **README.md**: Simplified to match v0.4 feature set — cleaner service table, feature list, install/build sections
- All 225 tests passing

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
- **Rename AgentBar → AgentBar**: project name, directories (`AgentBar/`, `AgentBarTests/`), bundle ID (`com.agentbar.app`), entitlements, `@main` struct, all imports, UI text, notification names
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


## Iteration 21: Gemini simplification + UI polish
- **Gemini daily-only window**: Removed 1-minute (RPM) rate window — only the daily (RPD) limit is meaningful for monitoring. Gemini now shows a single "1d" row like Z.ai shows "Qt", with `weeklyUsage: nil`.
- **Rename "Google Gemini CLI" → "Google Gemini"**: Updated `ServiceType.gemini` rawValue and Settings section header.
- **Settings cleanup**: Removed `geminiMinuteLimit` AppStorage and UI field. Only daily request limit remains configurable.
- **Popover focus ring fix**: Added `.focusable(false)` to settings gear button to prevent blue focus ring on popover open.
- All 41 tests passing


## Iteration 22: Z.ai dual-window (5h prompts + monthly MCP)
- **Z.ai dual rate windows**: API returns two limits — `TOKENS_LIMIT` (5h prompt window, percent-based) and `TIME_LIMIT` (monthly MCP allocation, request count). Previously only showed `TIME_LIMIT` as single "Qt" row.
  - `TOKENS_LIMIT` → `fiveHourUsage` (percent unit, API provides `percentage` and `nextResetTime` only)
  - `TIME_LIMIT` → `weeklyUsage` (requests unit, API provides `usage`/`currentValue`/`remaining`/`nextResetTime`)
- **ServiceType labels**: Changed Z.ai `fiveHourLabel` from "Qt" to "5h", `weeklyLabel` from "7d" to "MCP"
- **MetricRow label width**: Increased from 20px to 30px to accommodate "MCP" label without clipping
- **Fact-checked Z.ai plan info**: API confirmed Max plan (`level: "max"`), MCP total=4000 matches published quota, 5h window exists for prompts
- All 41 tests passing


## Iteration 23: Keep bars visible on fetch failure + CX 5h reset time fix
- **Bars persist on error**: `UsageViewModel.fetchAllUsage()` now returns zero-usage `UsageData` (instead of nil) when a configured provider throws. Previously, any API error or parsing failure removed the service bar entirely from the menu bar.
- **CX 5h reset time fix**: Codex `resets_at` in session JSONL is set once per session and becomes stale after the 5h window rolls over. Added `resolveWindow()` helper that advances a stale `resets_at` by `window_minutes` intervals until it's in the future. When the window has rolled over, usage is correctly zeroed but the next reset time is still shown.
- **Tests updated**: `testProviderFailureDoesNotAffectOthers` → `testProviderFailureReturnsZeroUsage`, `testEmptyResultsSetsError` → `testAllFailuresStillShowBars` — both now expect zero-usage entries instead of nil
- All 41 tests passing


## Iteration 24: GitHub Copilot + Cursor usage providers
- **ServiceType**: Added `.copilot` (GitHub Copilot) and `.cursor` (Cursor) cases with blue-600/green-600 colors, short names CP/CR, and `"Mo"` monthly label on `fiveHourLabel`
- **SubscriptionPlan**: Added `CopilotPlan` (Free/Pro/Pro+/Business/Enterprise/Custom) and `CursorPlan` (Free/Pro/Business/Custom) with monthly request limits
- **CopilotUsageProvider** (new): Calls `GET https://api.github.com/copilot_internal/user` with GitHub PAT from Keychain. Parses `premium_requests` quota snapshot (`entitlement - remaining = used`). Handles `unlimited: true` case. Reset = 1st of next month UTC. Single monthly window (`weeklyUsage: nil`)
- **CursorUsageProvider** (new): Reads JWT from SQLite DB at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, decodes `sub` claim for user ID, calls `GET https://www.cursor.com/api/usage?user={userId}` with session cookie. Sums `numRequests` across all model buckets (gpt-4, gpt-3.5-turbo, cursor-small, claude-3.5-sonnet). Reset parsed from `startOfMonth + 1 month`. Uses `import SQLite3` C API
- **project.yml**: Added `libsqlite3.tbd` dependency to both AgentBar and AgentBarTests targets
- **UsageViewModel**: Wired `CopilotUsageProvider` and `CursorUsageProvider` into `buildProviders()` with enable toggles and plan-based limits. Updated sort order: claude, codex, gemini, copilot, cursor, zai
- **SettingsView**: Added GitHub Copilot section (enable toggle, PAT SecureField) and Cursor section (enable toggle, plan picker, monthly limit field). Form height increased from 640 to 800
- **CopilotUsageProviderTests** (new): 6 tests — premium request parsing, reset time calculation, unlimited quota, missing credentials, 401 handling, header verification
- **CursorUsageProviderTests** (new): 5 tests — API usage parsing with temp SQLite DB, startOfMonth reset, missing database, null maxRequestUsage fallback, JWT decoding
- All 52 tests passing


## Iteration 25: Fix popover clipping + CLAUDE.md regression rules
- **Popover height fix**: Increased `DetailPopoverView` frame height from 350 to 480 to accommodate 6 services. Wrapped service `ForEach` in `ScrollView` so future service additions won't clip the footer (gear icon, "Last updated", Quit button)
- **CLAUDE.md updated**: Added "Visual smoke test" step (step 3) to workflow — must build+launch and verify popover UI after every change. Added "Regression prevention" section: check container sizes when adding items, never change fixed frames without verification, use ScrollView for growable lists. Updated provider list and service order to include Copilot/Cursor
- All 52 tests passing


## Iteration 26: Remove unnecessary API key fields + Copilot gh CLI + Cursor credit-based plans
- **Codex API key removed**: `CodexUsageProvider` reads only local JSONL files (`~/.codex/sessions/`) — API key was never used. Removed SecureField + Save button from Settings, removed `openaiAPIKey` state variable. Added caption "Usage is derived from local session logs"
- **Copilot gh CLI auto-read**: `CopilotUsageProvider` now tries `gh auth token` (via `Process`) first, falls back to manual PAT in Keychain. `readGHCLIToken()` runs `/usr/bin/env gh auth token` and captures stdout. Settings updated: primary note says "Token is auto-read from gh CLI", manual PAT moved to `DisclosureGroup` as optional fallback
- **Cursor credit-based plans**: Updated `CursorPlan` to reflect June 2025 pricing overhaul — Free/$0, Pro/$20, Pro+/$60, Ultra/$200, Teams/$40, Custom. Added `monthlyCreditDollars` and `monthlyRequestEstimate` (approximate, varies by model: ~225 for Claude Sonnet, ~500 for GPT-5 per $20). Renamed `monthlyRequestLimit` → `monthlyRequestEstimate` across provider, ViewModel, and Settings. Settings label changed to "Est. monthly requests" with explanatory caption
- All 52 tests passing


## Iteration 27: Fix Keychain password prompt on every launch
- **Root cause**: `KeychainManager` used legacy Keychain (login.keychain) without explicit ACL. Debug builds have ad-hoc code signing that changes each build, so macOS treats each build as a "new" app → prompts for login password every time, even after "Always Allow"
- **Attempted fix 1**: `kSecUseDataProtectionKeychain: true` — caused `-34018 errSecMissingEntitlement` because Data Protection Keychain requires proper code signing entitlements not available for ad-hoc Debug builds
- **Final fix**: Reverted to legacy Keychain but added `SecAccessCreate` with `nil` trusted app list to create an open-access ACL. This removes per-app restriction so any build of AgentBar can read items without password prompts
- **SettingsView compile fix**: Replaced `Result<Void, String>` (invalid — `String` doesn't conform to `Error`) with `SaveResult` enum
- All 72 tests passing


## Iteration 28: Safer keychain migration writes + unified save alert
- **Keychain migration safety**: `KeychainManager` now uses add-or-update upsert for Data Protection/legacy stores and no longer deletes legacy entries before confirming a successful write. Legacy cleanup happens only after a confirmed Data Protection write, preventing token loss on migration failure.
- **Fallback and delete semantics**: Save tolerates Data Protection entitlement failures by falling back to legacy storage; load still prioritizes Data Protection, then legacy with best-effort migration; delete now cleans both stores and only succeeds for expected statuses (`success`, `not found`, and Data Protection `missing entitlement`).
- **Single SwiftUI alert path**: `SettingsView` replaced dual `.alert` modifiers with one enum-driven `.alert(item:)` to avoid alert presentation conflicts.
- **Test coverage**: Added keychain behavior tests for legacy fallback + successful migration, failed migration preserving legacy item, and delete cleanup/error behavior using an injected mock security API.
- All 76 tests passing


## Iteration 29: Read Claude Code credentials via security CLI
- **Implementation provenance**: Source and test changes for this iteration landed in commit `126806a` (`ClaudeUsageProvider.swift`, `ClaudeUsageProviderTests.swift`). Commit `6c80cdf` updated this devlog entry only.
- **Problem**: `ClaudeUsageProvider` used `SecItemCopyMatching` to read `"Claude Code-credentials"` from Keychain. This item is owned by Claude Code CLI with a per-app ACL, so macOS prompts "AgentBar wants to use your confidential information" on every access. Ad-hoc code signing means "Always Allow" resets each build
- **Fix**: Replaced direct Keychain API with `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` via `Process`. The `security` binary is a system-trusted app that bypasses per-app ACL prompts. Same pattern as Copilot's `gh auth token`
- **Caching**: Added NSLock-guarded token cache with TTL matching the app's refresh interval, preventing repeated CLI invocations within the same polling cycle
- **`import Security` removed**: No longer needed since all Keychain access goes through the CLI
- **Test coverage**: Added 4 tests — CLI cache within TTL, cache nil on failure, valid JSON parsing, invalid JSON rejection
- All 85 tests passing


## Iteration 30: Fix Codex usage showing wrong values due to multiple limit_ids
- **Root cause**: Codex session JSONL files contain interleaved `rate_limits` records with different `limit_id` values (`"codex"` for the main model, `"codex_bengalfox"` for GPT-5.3-Codex-Spark). Code used the last record regardless of `limit_id`, so when `codex_bengalfox` (0% used) came after `codex` (14% used), usage showed 0%. The displayed reset timer also jumped between the two limit_ids' different `resets_at` values
- **Fix**: `extractLatestRateLimits` now tracks the last record per `limit_id` separately, then merges by summing `used_percent` and taking the earliest `resets_at` across all limit_ids. Single `limit_id` sessions still use the fast path (no merge overhead)
- **Model change**: Added `limit_id` field to `CodexRateLimits` struct for grouping
- **Test coverage**: Added 2 tests — multi-limit_id merge with sum verification and reset time selection, single-limit_id passthrough
- All 93 tests passing


## Iteration 31: Code signing with Developer ID Application certificate
- **project.yml**: Added `DEVELOPMENT_TEAM: <TEAM_ID>`, `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Developer ID Application"` to AgentBar target. Test target uses `"Apple Development"` identity with the same team ID to match Team IDs between host app and test bundle
- **Benefits**: Stable code signing identity across builds eliminates ad-hoc signing issues (Keychain ACL prompts, "Always Allow" not persisting). App is now properly signed for DMG distribution and notarization
- All 99 tests passing


## Iteration 32: Scope Developer ID signing to Release + add signing verification
- **Signing scope fix**: `project.yml` now uses automatic signing by default for `AgentBar`, with `Developer ID Application` manual signing restricted to `Release` config only. This avoids Debug/CI failures on machines without distribution certificates.
- **Test target portability fix**: Removed hard-pinned team/certificate from `AgentBarTests` and switched to automatic signing so tests can run across contributor and CI environments without a specific Apple team setup.
- **Release verification automation**: Added `scripts/verify-release-signing.sh` to archive a Release build and verify signing with `codesign --verify` and `spctl --assess`. Added the command to `CLAUDE.md` Build & Run section.
- All 103 tests passing


## Iteration 33: Add Phase 1 agent attention alerts (local notifications)
- **Roadmap documentation**: Added `docs/AGENT_ALERTING_ROADMAP.md` with detailed Phase 1/2/3 design, including event model, architecture, security posture, and test strategy.
- **Phase 1 alert pipeline**: Added normalized alert event model (`AgentAlertEvent`, `AgentAlertEventType`), detector protocol, Codex JSONL detector, monitor coordinator, and local notification service (`UserNotifications`) for real-time agent attention signals.
- **Codex event mapping**: Implemented Codex session parsing for `task_complete` (task done), escalation-required `function_call` (permission required), and question/decision-like `agent_message` prompts (decision required), with watermark-based incremental scanning.
- **Spam prevention and control**: Added per-event toggles, global enable switch, polling interval setting, and cooldown dedupe in `AgentAlertMonitor` to avoid repeated notifications from the same session/event key.
- **App integration and settings UI**: Wired monitor lifecycle into `AppDelegate` and added a new "Agent Alerts (Beta)" section in `SettingsView`, including notification permission request action.
- **Tests**: Added `CodexAlertEventDetectorTests` for task completion, escalation detection, decision prompt detection, and watermark filtering.
- All 111 tests passing


## Iteration 34: Phase 1.5 Claude hook ingestion + source toggles
- **Roadmap extended to Phase 1.5**: Updated `docs/AGENT_ALERTING_ROADMAP.md` with a new addendum for Claude Code hook ingestion (`Notification`/`Stop`/`SubagentStop`) and clarified the hybrid model (event-driven source + polling fallback).
- **Claude hook detector**: Added `ClaudeHookAlertEventDetector` to parse bridge JSONL records from `~/.claude/agentbar/hook-events.jsonl`, decode base64 payloads, and map them into normalized alert events (`taskCompleted`, `permissionRequired`, `decisionRequired`).
- **Monitor source toggles**: Extended `AgentAlertEventDetectorProtocol` with optional `settingsEnabledKey` and updated `AgentAlertMonitor` to skip disabled detectors. Default detectors now include both Codex session polling and Claude hook ingestion.
- **Settings UX updates**: Added alert source toggles (`alertCodexEventsEnabled`, `alertClaudeHookEventsEnabled`) and setup guidance in the "Agent Alerts (Beta)" section. Increased settings window height to preserve layout with new controls.
- **Claude hook bridge script**: Added `scripts/claude-hook-alert-bridge.sh` to capture raw Claude hook stdin payloads with a stable UTC capture timestamp and append them safely to the bridge JSONL file.
- **Tests**: Added `ClaudeHookAlertEventDetectorTests` (Stop/Notification mapping and boundary behavior) and added monitor coverage for disabled source toggles in `CodexAlertEventDetectorTests`.
- All 127 tests passing


## Iteration 35: Top-3 prioritized status bar rotation + Claude idle-session fallback
- **Status bar Top-3 prioritization**: Added `StatusBarDisplayPlanner` to rank services by usage (max of 5h/secondary window percentage), show only top 3 by default, and build a rotation sequence for overflow services.
- **Overflow rotation UX**: `StackedBarView` now renders paged rows and animates vertical slide transitions. Top page stays visible longer and is interleaved between overflow pages so high-usage services remain prioritized.
- **Claude usage reset fix**: `ClaudeUsageProvider` no longer hard-resets to 0% when API returns `five_hour`/`seven_day` as null during idle periods. It now caches last valid window metrics in `UserDefaults` and reuses them until their reset time passes.
- **Test coverage**: Added `StatusBarDisplayPlannerTests` (ranking, paging, Top-page interleaving, durations) and expanded `ClaudeUsageProviderTests` with cache fallback and cache-expiry cases. Updated provider tests to use isolated `UserDefaults` suites.
- **Signing check**: Ran `./scripts/check-signing-matrix.sh` to verify Debug/Release signing matrix is still correct.
- All 134 tests passing


## Iteration 36: Continuous Top-3-first scroll + Claude idle-window parsing hardening
- **Status bar behavior correction**: Reworked menu bar rendering to a continuous vertical list with fixed row height, 3-row viewport, and step-by-step downward scrolling through overflow rows. After reaching the bottom window, it returns to Top 3 and holds before repeating.
- **Hover interaction**: Added hover handling so mouseover immediately snaps to Top 3 and pauses scrolling while hovered.
- **Claude idle-session bug fix**: Expanded OAuth usage decoding to support model-scoped keys (`five_hour_*`, `seven_day_*`) when aggregate keys are absent, and kept cache fallback for transient null windows. This prevents false 0%/missing reset regressions when no active session exists.
- **Test updates**: Added model-scoped Claude window test coverage and updated status bar planner tests for continuous-scroll semantics (`maxScrollIndex`, ranking, tie-break, visibility behavior).
- All 136 tests passing


## Iteration 37: Precise Top reset + Claude decode-fallback cache resilience
- **Exact Top reset behavior**: Removed implicit offset animation in `StackedBarView` and kept explicit step animations only. Bottom-to-top transition and hover reset now always jump directly to offset `0` in a no-animation transaction.
- **Hover freeze semantics**: While hovered, the status bar repeatedly enforces Top position and suppresses all scroll progression until hover exits.
- **Claude payload hardening**: `ClaudeUsageProvider` now treats unexpected 200-response payload shapes as an empty usage payload instead of throwing decode errors, allowing existing cache fallback logic to preserve valid 5h/7d values during idle/temporary API shape drift.
- **Test coverage**: Added `testUsesCachedValuesWhenResponsePayloadIsUnexpected` and retained idle-window cache preference tests for zero/null edge cases.
- All 139 tests passing


## Iteration 38: Fix Top-row clipping by correcting viewport and host alignment
- **Viewport alignment fix**: `StackedBarView` now applies the 20px viewport frame with `.top` alignment instead of the default center alignment, so `offset 0` truly maps to the first row at the top edge without partial clipping.
- **Status button host layout fix**: `StatusBarController` no longer overwrites the system-managed status button frame. The SwiftUI host view is now pinned to `button.bounds` (with horizontal inset) and autoresizes with the button, preventing vertical misalignment in the menu bar slot.
- All 139 tests passing


## Iteration 39: Rename CCUsageBar to AgentBar
- **Project-wide rename**: Replaced all occurrences of `CCUsageBar` → `AgentBar`, `ccusagebar` → `agentbar`, and `CCUSAGEBAR` → `AGENTBAR` across 28+ files including pbxproj, project.yml, Swift sources, tests, scripts, and docs
- **File renames**: `CCUsageBarApp.swift` → `AgentBarApp.swift`, `CCUsageBar.entitlements` → `AgentBar.entitlements`
- **Directory renames**: `CCUsageBar/` → `AgentBar/`, `CCUsageBarTests/` → `AgentBarTests/`, `CCUsageBar.xcodeproj/` → `AgentBar.xcodeproj/`
- **Data paths updated**: `~/.claude/ccusagebar/` → `~/.claude/agentbar/`, env var `CCUSAGEBAR_CLAUDE_HOOK_LOG` → `AGENTBAR_CLAUDE_HOOK_LOG`
- **Keychain service unchanged**: `com.agentbar.apikeys` was already the correct name
- All 139 tests passing


## Iteration 40: Socket listener + custom sound support
- **AlertSocketListener**: Unix domain socket at `~/.agentbar/events.sock` replaces Timer-based polling as primary event source. Accepts newline-delimited JSON with normalized agent/event/session_id/message/timestamp fields.
- **AlertSoundManager**: CESP-compatible sound pack loader with `openpeon.json` manifest parsing, per-category enable/disable, no-repeat selection, and AVAudioPlayer playback with configurable volume.
- **AgentAlertMonitor refactored**: Removed Timer.publish polling loop and pollingInterval property. Socket listener is primary event source; CodexAlertEventDetector retained as fallback for users without hook configuration. New `receive(event:)` method handles push-based events with same dedup/cooldown/settings filtering.
- **AgentAlertNotificationService**: Integrated AlertSoundManager — custom sound plays instead of system default when sound pack configured.
- **Hook scripts**: `scripts/agentbar-hook.sh` (Claude) and `scripts/agentbar-codex-hook.sh` (Codex) send normalized JSON to socket with JSONL file fallback.
- **SettingsView**: Removed polling interval picker; added Alert Sounds subsection with pack directory browser, volume slider, per-category toggles, and test buttons. Updated help text for socket-based architecture.
- **AgentAlertEvent**: Added `cespCategory` property for event-type-to-sound-category mapping.
- All 170 tests passing


## Iteration 41: Review fixes — socket rewrite, fallback timer, sound auto-restore
- **AlertSocketListener rewritten**: Replaced NWListener/Network framework with POSIX sockets (`socket(AF_UNIX, SOCK_STREAM, 0)`) + `DispatchSource.makeReadSource`. Fixes POSIX error 22 at runtime and race conditions — all mutable state serialized on private `DispatchQueue` with `queue.sync` for public accessors.
- **Fallback timer restored**: Reintroduced 10s fallback `Timer.publish` in `AgentAlertMonitor` for detector-based polling (Codex file watcher, Claude JSONL reader). Socket is primary, timer is secondary for users without hook configuration.
- **ClaudeHookAlertEventDetector restored**: Re-added to default detector list so Claude JSONL fallback bridge events are still consumed.
- **AlertSoundManager auto-restore**: Added `restorePersistedPack()` in `init()` so persisted sound pack path is reloaded after app restart.
- **Hook scripts hardened**: Rewrote both `agentbar-hook.sh` and `agentbar-codex-hook.sh` to construct all JSON via `python3 json.dumps` (prevents unescaped session_id injection).
- **New tests**: `testAutoRestoresPersistedPackOnInit` and `testDoesNotCrashOnInitWithInvalidPersistedPath` added to `AlertSoundManagerTests`.
- All 172 tests passing


## Iteration 42: Review fixes — socket FD race, client tracking, EAGAIN handling
- **Cancel handler FD race fixed**: Cancel handler now captures server FD value at creation time instead of reading `self.serverFD`, preventing a restart race where the old cancel handler could close the new listener's FD.
- **Client connection tracking**: Active client `DispatchSourceRead` instances tracked in `clientSources` dictionary. `_stop()` cancels all client sources and closes FDs. Client cancel handler properly calls `close(clientFD)`.
- **Synchronous `_isListening` reset**: `_isListening` set to `false` immediately in `_stop()` so `AgentAlertMonitor` sees correct state without waiting for async cancel handler.
- **EAGAIN/EWOULDBLOCK handling**: Non-blocking `read()` now distinguishes `bytesRead == 0` (EOF) from `bytesRead < 0` with `errno == EAGAIN` (transient, retry) vs real error (close).
- **Hook script python3 fallback**: Both hook scripts now fall back to safe printf-based JSON with quote-stripped values when `python3` is unavailable.
- **Lifecycle tests**: Added 5 tests for socket listener start/stop, rapid restart, double stop, and synchronous `isListening` state.
- All 177 tests passing


## Iteration 43: Brighten Codex bar text color
- **Codex darkColor brightened**: Changed from emerald-600 `(0.020, 0.588, 0.412)` to emerald-500 `(0.063, 0.725, 0.506)` for better readability of the "CX" label and bar fill in the menu bar.
- All 183 tests passing


## Iteration 44: Codebase cleanup — remove dead code, consolidate duplicates
- **Dead code removed**: `APIClient.getRawData`, `APIError.timeout`/`.networkError`, `UsageViewModel.consecutiveFailures`, `DateUtils.isWithinFiveHourWindow`/`isWithinWeeklyWindow`/`nextResetTime`/`nextResetAligned`, `CopilotPlan.monthlyPremiumRequests`, `CursorPlan.monthlyCreditDollars`
- **Shared UserDefaultsExtensions.swift**: Consolidated 3 identical `bool(forKey:defaultValue:)` definitions (AgentAlertMonitor, UsageViewModel, AgentAlertNotificationService) into one `internal` extension
- **Shared DynamicCodingKey.swift**: Extracted identical `DynamicCodingKey` struct from ClaudeUsageProvider and CursorUsageProvider into shared utility
- **Protocol-level passesBoundary**: Moved duplicate `passesBoundary` from ClaudeHookAlertEventDetector and CodexAlertEventDetector into `AgentAlertEventDetectorProtocol` extension
- **AlertSoundManager deduplication**: `cespCategory(for:)` now delegates to `AgentAlertEventType.cespCategory`; volume reading extracted to `currentVolume` computed property
- **Tests cleaned**: Removed 6 test methods for removed DateUtils functions
- All 179 tests passing


## Iteration 45: Remove focus ring from Quit button in popover
- **Focus ring removed**: Added `.focusable(false)` to the Quit button in `DetailPopoverView`. macOS was auto-focusing the last focusable button when the popover opened, causing a blue border to appear around Quit (or sometimes the gear icon). The gear button already had `.focusable(false)`.
- All 183 tests passing

## Iteration 46: Settings tab split, sound pack help, plan display in popover
- **SettingsView TabView**: Split monolithic 8-section Form into two tabs — "Usage" (General + 6 service sections) and "Alerts" (alert toggles + sound pack). Frame reduced from 450×920 to 450×750
- **ClaudePlan enum**: Added `ClaudePlan` (Free/Pro/Max/Team) to `SubscriptionPlan.swift` with `@AppStorage("claudePlan")` picker in Claude Code settings section
- **CodexPlan.plus**: Added `case plus = "Plus"` with 1M/5h and 10M/7d token limits before `pro`
- **planName on UsageData**: New `let planName: String?` field with default `nil` — all existing call sites unchanged
- **Provider planName population**: Claude/Codex/Cursor read from UserDefaults; Copilot reads `copilot_plan` from API response with `capitalizedPlanName()` helper
- **Popover plan display**: `ServiceDetailRow` shows plan name as caption-sized secondary text next to service name (e.g. "Claude Code Pro")
- **SoundPackHelpSheet**: `questionmark.circle` button on "Alert Sounds" DisclosureGroup label opens `.sheet` with CESP directory structure, manifest JSON schema, supported audio formats (WAV/MP3/AIFF/M4A/CAF), and category explanations
- **Tests added**: `CodexPlan.plus` limits, `ClaudePlan` enum validity/round-trip, `CopilotUsageProvider.capitalizedPlanName`, Copilot planName assertions
- All 184 tests passing


## Iteration 47: Z.ai plan auto-detect, Claude Max 5x/20x split
- **Z.ai auto-detection**: Wired existing `ZaiQuotaData.level` field (already decoded but unused) to `UsageData.planName` via `capitalizedPlanName()` helper — plan now appears in popover automatically from API
- **Claude Max 5x/20x split**: Changed `ClaudePlan.max` to `.max5x = "Max 5x"` and `.max20x = "Max 20x"` for distinct tier selection. Added `migrateLegacyClaudePlanIfNeeded()` to convert stored "Max" → "Max 5x"
- **Settings help text**: Updated Copilot ("Plan is auto-detected from GitHub API") and Z.ai ("Plan and limits are auto-detected from Z.ai API") section captions
- **Auto-detect summary**: Copilot and Z.ai are fully automatic; Claude/Codex/Cursor remain manual pickers (APIs don't expose plan info)
- **Tests added**: `testZaiCapitalizedPlanName`, `testClaudePlanLegacyMaxMigratesTo5x`, updated `testClaudePlanEnumHasExpectedCases` for 5 cases
- All 186 tests passing


## Iteration 48: Ensure planName always shows for configured services
- **Default planName for manual providers**: Claude/Codex/Cursor providers now fall back to default plan (`.pro`) when UserDefaults has no stored value, instead of returning nil. Previously planName only appeared after opening Settings at least once
- **Copilot nil fallback**: When API returns `copilot_plan: null`, defaults to "Free" instead of showing nothing
- **Gemini unchanged**: No plan concept — planName stays nil (no label shown)
- All 186 tests passing


## Iteration 49: Rename Alert → Notification terminology
- **Renamed models**: `AgentAlertEvent` → `AgentNotifyEvent`, `AgentAlertEventType` → `AgentNotifyEventType`
- **Renamed infrastructure**: `AgentAlertMonitor` → `AgentNotifyMonitor`, `AgentAlertNotificationService` → `AgentNotifyNotificationService`, `AlertSocketListener` → `NotifySocketListener`, `AlertSoundManager` → `NotifySoundManager`
- **Renamed detectors**: `AgentAlertEventDetectorProtocol` → `AgentNotifyEventDetectorProtocol`, `CodexAlertEventDetector` → `CodexNotifyEventDetector`, `ClaudeHookAlertEventDetector` → `ClaudeHookNotifyEventDetector`
- **Renamed tests**: All 4 alert-related test files renamed to `*Notify*` equivalents
- **UI text updates**: "Agent Alerts (Beta)" → "Agent Notifications (Beta)", "Alerts" tab → "Notifications" tab, "Enable alerts" → "Enable notifications", "Alert Sounds" → "Notification Sounds"
- **UserDefaults keys**: All `alert*` keys renamed to `notification*` (e.g., `alertsEnabled` → `notificationsEnabled`, `alertSoundPackPath` → `notificationSoundPackPath`)
- **Notification.Name**: `.alertsSettingsChanged` → `.notificationsSettingsChanged`
- **AppDelegate**: `alertMonitor` → `notifyMonitor`
- All 186 tests passing


## Iteration 50: Split agent sources into separate section, add help sheet, Z.ai cache TTL
- **Agent Sources section**: Moved Codex file watcher and Claude hook toggles from "Agent Notifications (Beta)" into a dedicated "Agent Sources" section, since they are agent-specific configuration
- **Help sheet**: Removed inline description captions (socket path, hook script setup, codex fallback) from the notifications UI and added a `?` button on the Agent Sources header that opens `AgentSourcesHelpSheet` with full documentation
- **Z.ai response cache**: Added 60-second minimum cache TTL to `ZaiUsageProvider` via `cachedIfFresh()`/`updateCache()` static methods, preventing excessive API requests when refresh interval is below 60s
- All 186 tests passing


## Iteration 51: Enable launch at login by default
- **Default changed**: `launchAtLogin` default value from `false` → `true`
- **First-launch registration**: Added `registerLoginItemIfNeeded()` in `AppDelegate` — on first launch (when UserDefaults key is absent), writes the default and calls `LoginItemManager.setEnabled(true)` to actually register the login item
- All 186 tests passing


## Iteration 52: Fix recurring button focus ring in popover
- **Removed FocusState**: Deleted `@FocusState`, `PopoverButton` enum, and `.focused()` modifiers from `DetailPopoverView` — these explicitly registered buttons as focus targets, causing the ring to shift between buttons whenever one was removed
- **Clear first responder on open**: Added `makeFirstResponder(nil)` in `PopoverController.show()` after the popover is displayed, so no element receives keyboard focus when the popover appears
- All 186 tests passing


## Iteration 53: Add Z.ai usage provider test coverage
- **New test suite**: Added `ZaiUsageProviderTests` to cover Z.ai quota parsing, plan capitalization, keychain configuration detection, and cache TTL behavior
- **Auth retry verification**: Added API mock protocol assertions for Bearer-first then raw-key retry flow when receiving `401 Unauthorized`
- **Error-path coverage**: Added tests for missing API key (`APIError.unauthorized`) and malformed quota payload without limits (`APIError.noData`)
- **Cache behavior checks**: Added tests that verify `cachedIfFresh` expiration and `fetchUsage` short-circuiting to cache without network calls
- All 194 tests passing


## Iteration 54: Fix Z.ai tests deleting real keychain data
- **Root cause**: `ZaiUsageProviderTests` called `KeychainManager.delete(account: "zai")` in setUp/tearDown, which deleted the user's real Z.ai API key from the keychain — causing Z.ai to disappear from the popover after running tests
- **credentialProvider injection**: Added `credentialProvider` closure parameter to `ZaiUsageProvider.init()`, matching the pattern used by `CopilotUsageProvider`. Production code defaults to reading from `KeychainManager`, tests inject mock credentials via closure
- **Test rewrite**: Removed all `KeychainManager.save/delete` calls from `ZaiUsageProviderTests`. Tests now use `makeProvider(credential:)` helper that injects credentials without touching the real keychain
- **isConfigured()**: Now uses the injected `credentialProvider()` instead of directly calling `KeychainManager.load()`
- All 186 tests passing


## Iteration 55: Agent notification hook reliability + OpenCode first-class source
- **Legacy settings migration on launch**: Added `AgentNotifySettingsMigrator` and wired `AgentNotifySettingsMigrator.migrateIfNeeded()` in `AppDelegate.applicationDidFinishLaunching`. Migrates `alert*` keys to `notification*` keys and removes old keys after migration.
- **Codex hook config detection hardening**: Added `AgentHookConfigurationChecker` and settings status UI. Codex `notify` is now validated only at TOML top-level (table-local `notify` is treated as unconfigured).
- **Agent Sources UI upgrade**: Added hook status rows + manual re-check action, OpenCode source toggle (`notificationOpencodeHookEventsEnabled`), and help sheet sections for OpenCode + safe installer usage.
- **Socket/monitor observability**: Added structured `os.log` diagnostics across `NotifySocketListener`, `AgentNotifyMonitor`, and `AgentNotifyNotificationService` for drop reasons, lifecycle, posting, and auth checks.
- **Deduplication robustness**: `AgentNotifyEvent.dedupeKey` now prefers normalized `sessionID`, falls back to normalized message hash, then timestamp bucket when both are missing.
- **OpenCode first-class service type**: Added `ServiceType.opencode` (name/color/shortName/keychain account), switched socket mapping from Cursor alias to dedicated OpenCode service, and included OpenCode in ordering (`UsageViewModel`, `StatusBarDisplayPlanner`).
- **New/updated hook scripts**:
- `scripts/agentbar-gemini-hook.sh`: Improved event normalization (`AfterAgent`/`SessionEnd`, `Notification + ToolPermission`, `prompt_response` support).
- `scripts/agentbar-opencode-hook.sh`: New OpenCode JSON hook adapter (`session.idle`/`session.completed`/`permission.asked`/`question.asked`/`session.error`).
- `scripts/install-agent-hooks.sh`: New safe installer for Codex/Claude/Gemini/OpenCode with pre-write backup to `~/.agentbar/backups/<UTC timestamp>/`, merge-based updates, and OpenCode plugin generation.
- **OpenCode plugin event coverage**: Installer-generated plugin now forwards `session.completed` in addition to idle/permission/question/error events.
- **Tests**: Added `AgentHookConfigurationCheckerTests` + `AgentNotifySettingsMigratorTests`; expanded `AgentNotifyEventTests` (dedupe fallbacks) and `NotifySocketListenerTests` (OpenCode mapping + source toggle behavior).
- **Verification**: Targeted suite run passed (`AgentHookConfigurationCheckerTests`, `AgentNotifySettingsMigratorTests`, `AgentNotifyEventTests`, `NotifySocketListenerTests`, `StatusBarDisplayPlannerTests`) — 32 tests, 0 failures.

## Iteration 56: OSS hardening for signing secrets + history cleanup
- **Team ID de-hardcode**: Removed hardcoded `DEVELOPMENT_TEAM` from `project.yml` and `AgentBar.xcodeproj/project.pbxproj`. Release signing scripts now require `DEVELOPMENT_TEAM` via environment variable instead of embedding a value in tracked files.
- **Release script guardrails**: Updated `scripts/verify-release-signing.sh` and `scripts/release.sh` to fail fast with a clear message when `DEVELOPMENT_TEAM` is missing. Added parser coverage in `scripts/test-verify-release-signing.sh`.
- **CI secret scanning**: Added `.github/workflows/secret-scan.yml` to run `gitleaks` against full git history on PRs and `main` pushes.
- **Documentation**: Updated `CLAUDE.md` release signing command to include `DEVELOPMENT_TEAM=YOUR_TEAM_ID` and documented this hardening step in DEVLOG.
- **History rewrite**: Rewrote repository history with `git filter-repo` to remove sensitive identifiers (team ID literal and personal alias) from blobs and commit/tag messages.
- All 203 tests passing

## Iteration 57: Agent notification settings simplification + source-aware preview
- **Notification event toggles simplified**: Settings now expose two event toggles only: `Task completed` and `Input required`. `permissionRequired` and `decisionRequired` remain distinct event types internally but share one title and one settings key.
- **Unified settings key migration**: Added migration to map legacy input toggles (`notificationPermissionRequiredEnabled`, `notificationDecisionRequiredEnabled`, `alertPermissionRequiredEnabled`, `alertDecisionRequiredEnabled`) into `notificationInputRequiredEnabled`, then delete old keys.
- **Message source identification improved**: Notification body prefix now uses a source tag with agent and optional session context (e.g. `[OpenAI Codex | session-1]`). Long session IDs are compacted for readability.
- **Settings UX alignment**: Notifications section now focuses on `Enable notifications`, `Task completed`, `Input required`, and `Show message preview`, while `Agent Sources` and `Notification Sounds` sections remain source/sound-specific.
- **Tests**: Updated notification body assertions to use source tags and added migration coverage for alert-era input keys.
- All 208 tests passing

## Iteration 58: OpenCode plugin reliability fix for Agent notifications
- **Root issue area**: OpenCode notifications relied on spawning `agentbar-opencode-hook.sh` from plugin runtime; if process spawn/runtime environment failed silently, OpenCode events were dropped while other agents still worked.
- **Plugin transport rewrite**: Installer now generates `~/.config/opencode/plugins/agentbar-notify.js` that writes normalized events directly to `~/.agentbar/events.sock` via `node:net` instead of shelling out per event.
- **Event normalization hardening**: Added robust mapping and field extraction for `session.idle/session.completed`, `permission.asked`, and input/error variants; supports both `input.event` and direct event-shaped payloads.
- **Safe install behavior preserved**: Re-running `scripts/install-agent-hooks.sh` still creates timestamped backups before modifying plugin files.
- **Verification**: `bash -n scripts/install-agent-hooks.sh` passed, installer updated plugin with backup, and local dry-run confirmed plugin emits normalized OpenCode payloads over Unix socket.

## Iteration 59: OpenCode event model aligned to two-category notifications
- **Two-category alignment**: OpenCode permission prompts are now normalized as `decision` (input-required) rather than a separate `permission` category, matching the app's simplified notification model (`task completed` vs `input required`).
- **Hook script update**: `scripts/agentbar-opencode-hook.sh` now maps `permission.asked`/`permission`/`required_permission` to `decision`.
- **Installer plugin update**: Generated OpenCode plugin from `scripts/install-agent-hooks.sh` now applies the same mapping so runtime behavior matches hook script behavior.
- **Regression test**: Added `HookScriptFallbackTests.testOpenCodeHookMapsPermissionAskedToDecisionWithoutPython3` to verify OpenCode payload normalization without python3 dependency.

## Iteration 60: Build version identifier in popover footer
- **Run Script build phase**: Added "Embed Git Version Info" phase that injects `GitCommitHash` (and `GitVersionTag` if present) into the built product's Info.plist via PlistBuddy
- **Footer version display**: `DetailPopoverView` now shows a version identifier below "Last updated" — displays git tag if available, otherwise short commit hash, in `.caption2` `.tertiary` style
- **Static computation**: Version string is computed once via `static let` from `Bundle.main.infoDictionary` for zero runtime cost
- All 209 tests passing


## Iteration 61: Add Buy Me a Coffee button in popover
- **BMC support button**: Added centered "Buy Me a Coffee" button between usage section and footer in `DetailPopoverView`. Opens `https://buymeacoffee.com/_scari` in default browser on click.
- **Styling**: Orange `.bordered` button with coffee cup icon, centered in popover width
- All 209 tests passing

## Iteration 62: Harden BMC action testability and coverage
- **Injectable URL opener**: `DetailPopoverView` now accepts an `openExternalURL` closure (defaulting to `NSWorkspace.shared.open`) so external-link behavior is testable without launching a browser.
- **Deterministic action verification**: Added `triggerBMCForTesting()` behind `#if DEBUG` to exercise the same BMC action path in unit tests.
- **New regression test**: Added `DetailPopoverViewTests.testBuyMeACoffeeActionOpensExpectedURL` to verify the BMC action opens `https://buymeacoffee.com/_scari`.
- All 210 tests passing

## Iteration 63: Popover usage ranking by consumption + release-focused tests
- **Popover ordering fix**: `DetailPopoverView` now renders usage rows with a consumption-based ranking (`DetailPopoverView.sortedForDisplay`) instead of fixed service order, so highest-usage agents appear first.
- **Ranking consistency**: Popover ranking uses the same score/tie-break policy as status bar ranking (`max(5h, weekly)` then service order), while keeping unavailable rows visible in the popover.
- **Coverage added**: Added `DetailPopoverViewTests.testSortedForDisplayOrdersByHighestUsageDescending`, `DetailPopoverViewTests.testSortedForDisplayUsesServiceOrderAsTieBreaker`, and `DetailPopoverViewTests.testSortedForDisplayKeepsUnavailableRows`.
- All 213 tests passing

## Iteration 64: SVG icon automation for README/DMG packaging
- **Icon pipeline script**: Added `scripts/generate-icons.sh` to generate app icon assets from `docs/assets/agentbar-icon.svg`.
- **Output formats**: Script produces `1024` master PNG, resized PNG set (`16` through `1024`), `.iconset`, and `.icns` under `build/icons/`.
- **Renderer fallback**: SVG rendering automatically falls back across available tools (`rsvg-convert`, `inkscape`, `magick`, `sips`, `qlmanage`).
- **ICNS fallback**: Uses `iconutil` when available and falls back to `python3 + Pillow` when `iconutil` rejects iconset conversion in the local environment.
- **README docs**: Added concise icon-generation usage and output paths.

## Iteration 65: CESP sound pack registry integration
- **Build flag**: Added `AGENTBAR_NOTIFICATION_SOUNDS` compilation condition (ON in Debug, OFF in Release) to gate all notification sound functionality; wrapped `NotifySoundManager`, `AgentNotifyNotificationService` sound calls, `SettingsView` sound sections, and `NotifySoundManagerTests` with `#if` guards
- **CESPManifest dual format**: Updated `CESPManifest` to support both real CESP format (`categories.*.sounds[].{file, label}`) and legacy format (`sounds: [String: [String]]`), with `soundFiles(for:)` helper method
- **CESPRegistryPack model**: New `CESPRegistryPack` (Decodable, Sendable, Identifiable) with computed `formattedSize`, `baseContentURL`, `manifestURL` properties; `CESPRegistryIndex` wrapper
- **CESPRegistryService**: Actor-based registry fetcher with 1-hour cache, fetching from `peonping.github.io/registry/index.json`
- **CESPPackDownloadService**: Actor-based download service storing packs to `~/.openpeon/packs/{name}/`; downloads manifest then each sound file with progress callback; cleans up partial downloads on failure
- **SoundPackViewModel**: `@MainActor ObservableObject` managing registry loading, pack selection, download progress, and activation via `NotifySoundManager`
- **Settings UI refactoring**: Replaced NSOpenPanel file browser with Picker dropdown from CESP registry; added download progress bar, error display, and refresh button; removed `chooseSoundPackDirectory()` method
- **New tests**: `CESPRegistryPackTests` (8 tests), `CESPPackDownloadServiceTests` (4 tests with `MockURLProtocol`), 5 new `NotifySoundManagerTests` for real CESP format, display name, and fallback behavior
- All 231 tests passing

## Iteration 66: Sound pack settings UI enhancement
- **Language filter**: Added `selectedLanguage` and `filteredPacks` to `SoundPackViewModel`; `availableLanguages` computed from pack list; Language Picker in settings filters pack dropdown
- **Agent sound overrides**: Per-agent (Claude, Codex, OpenCode) sound pack selection with Default/None/pack options; stored in UserDefaults as `notificationSoundPackName_{keychainAccount}` and `notificationSoundPackPath_{keychainAccount}`
- **NotifySoundManager refactored**: `play(for:service:)` resolves agent-specific pack path before falling back to global; added `resolvePackPath(for:)` and manifest cache (`resolveManifest(at:)`); removed `isCategoryEnabled()` as category toggles were redundant with notification-level toggles
- **AgentNotifyNotificationService**: Passes `event.service` to `NotifySoundManager.play(for:service:)` for per-agent sound routing
- **SettingsView cleanup**: Removed `notificationSoundTaskCompleteEnabled`/`notificationSoundInputRequiredEnabled` toggles; added Language picker, Agent Sound Overrides DisclosureGroup; moved Volume slider to section bottom; Test buttons retained
- **Tests**: Added agent-override tests (`testPlayReturnsFalseWhenAgentSetToNone`, `testPlayUsesGlobalPackWhenNoAgentOverride`, `testPlayReturnsFalseWhenNoPackConfiguredWithService`); language filtering tests in CESPRegistryPackTests (`testLanguageFieldDecodes`, `testLanguageFilteringOnPacks`, `testAvailableLanguagesFromPacks`)
- All 236 tests passing

## Iteration 67: Sound settings polish — language display, multi-lang, style, test buttons
- **Language display**: Language picker shows original codes (e.g., "en", "zh-CN") as-is
- **Multi-language packs**: `availableLanguages` and `filteredPacks` now split comma-delimited language fields (e.g., "en,ru"); silicon_valley pack appears under both en and ru filters
- **Section style consistency**: Notification Sounds section converted from `DisclosureGroup` wrapper inside `Section` to `Section { ... } header: { ... }` pattern matching Agent Sources section
- **Test buttons with agent overrides**: `playTest(category:service:)` now uses `resolvePackPath(for:)` + `resolveManifest(at:)` for consistent path resolution; per-agent play buttons (play.circle icon) added to Agent Sound Overrides rows; global Test buttons test the global pack
- **Tests**: Added `testMultiLanguageFilteringIncludesCommaDelimited`, `testAvailableLanguagesSplitsCommaDelimited`
- All 239 tests passing

## Iteration 68: Notification card readability refresh
- **Title redesign**: Notification title now shows the agent/service name (for example `OpenAI Codex`, `Claude Code`) instead of a generic event title.
- **Body redesign**: Notification body now starts with explicit state (`Task completed` or `Input required`) and then appends detail text.
- **Session tag removal**: Removed the `[service | session]` prefix from notification body to avoid long, low-signal identifiers in cards.
- **Preview copy update**: Settings copy now clarifies that preview mode shows agent output text in the notification body.
- **Coverage update**: Added content-level assertions for both title and body formatting in `AgentNotifyNotificationServiceTests`.
- All 240 tests passing

## Iteration 69: Move Agent Sound Overrides below test buttons
- **Layout reorder**: Moved Agent Sound Overrides DisclosureGroup below the Test buttons row in Notification Sounds section for better visual flow (Language → Pack → Progress/Error → Test → Overrides → Volume)
- All 239 tests passing


## Iteration 70: Test suite consolidation for faster execution
- **Removed Mock API validation tests** (4 tests): `testMockKeychainSecurityAPIRejectsMalformedCopyQuery`, `testMockKeychainSecurityAPIRejectsMalformedAddQuery`, `testMockKeychainSecurityAPIRejectsMalformedUpdateQuery`, `testMockKeychainSecurityAPIRejectsMalformedDeleteQuery` — these tested the mock itself, not production code
- **Consolidated Keychain load tests** (4 → 1): Merged `testKeychainLoadDoesNotFallbackToLegacyOnUnexpectedDataProtectionFailure`, `testKeychainLoadFallsBackToLegacyOnMissingEntitlementAndKeepsLegacyWhenMigrationFails`, `testKeychainLoadMigratesLegacyItemWhenDataProtectionSaveSucceeds`, `testKeychainLoadKeepsLegacyItemWhenMigrationSaveFails` into single `testKeychainLoadMigrationBehavior`
- **Consolidated Plan enum tests** (5 → 1): Merged `testCodexPlanPlusLimits`, `testCodexPlanAllCasesIncludesPlus`, `testClaudePlanEnumHasExpectedCases`, `testClaudePlanRoundTrips`, `testClaudePlanLegacyMaxMigratesTo5x` into single `testPlanEnumsRoundTripAndHaveExpectedCases`
- **Test count**: 236 → 225 (11 tests removed via consolidation)
- All 225 tests passing

## Iteration 71: Add explicit mute mode for Agent notifications
- **Notification sound mode setting**: Added `notificationSoundMode` (`system` / `mute`) and exposed it in Settings > Notifications > Agent Notifications as a dedicated `Notification sound` picker with `Mute` option.
- **Silent-but-visible notifications**: `AgentNotifyNotificationService` now resolves `NotificationSoundMode` per-post and sets `content.sound = nil` when mode is `mute`, preventing both custom sound pack playback and macOS default notification sound while still posting the notification.
- **Settings data hygiene**: Added invalid-value sanitization in `SettingsView.onAppear` so unknown stored sound mode values fall back to `system`.
- **Behavioral test coverage**: Extended `AgentNotifyNotificationServiceBehaviorTests` with `testPostMutesSoundWhenSoundModeIsMute` to verify mute mode suppresses sound payloads.
- All 253 tests passing

## Iteration 72: Reorder notification settings sections
- **Notification Sounds placement**: Moved the `Notification Sounds` section above `Agent Sources` in the Notifications tab (`SettingsView.notificationsTab`) so sound controls appear earlier in the workflow.
- **No behavior changes**: Kept existing sound/source toggles and handlers unchanged; this is a presentation-order update only.
- All 253 tests passing

## Iteration 73: Add BMC hide setting in Usage Settings
- **Usage tab setting added**: Added `Hide Buy Me a Coffee button` toggle at the bottom of Usage Settings (`Support` section) backed by `hideBuyMeACoffeeButton`.
- **User-facing guidance copy**: Added descriptive text for donors: "If you've already donated and the BMC button feels distracting, you can hide it."
- **Popover behavior wired**: `DetailPopoverView` now reads the same setting and conditionally hides the `Buy Me a Coffee` CTA while keeping the rest of footer/layout unchanged.
- **Regression coverage**: Added `DetailPopoverViewTests` coverage for hidden/visible state via debug helper.
- All 255 tests passing

## Iteration 74: Fix popover version fallback to commit hash when no tag exists
- **Build pipeline fix**: Regenerated `AgentBar.xcodeproj` from `project.yml` so the `Embed Git Version Info` post-build script is actually present in the project and runs on every build.
- **Info.plist injection verified**: Confirmed Debug build output now writes `GitCommitHash` (for untagged commits) and keeps `GitVersionTag` absent when no exact tag exists, preventing unintended fallback to `CFBundleShortVersionString` (`1.0`).
- **Version resolution hardened**: Refactored `DetailPopoverView` version logic into `resolvedVersionString(from:)` with whitespace-safe normalization and explicit fallback order: tag → commit hash → short version → `unknown`.
- **New tests**: Added `DetailPopoverViewTests` coverage for version priority rules and missing-value fallback behavior.

## Iteration 75: Align daily heatmap tiles and trend chart box vertically
- **Shared sizing constants**: Introduced shared tile/spacing constants in `UsageHistoryTabView` and derived `heatmapGridHeight` from those values.
- **Top-edge alignment fix**: Removed the standalone title row above the line chart so the chart box starts at the same vertical origin as the daily heatmap grid.
- **Height alignment fix**: Set the trend chart box height to match the computed heatmap grid height, ensuring the two visual boxes align vertically.
- **Future-proofing**: Replaced hardcoded heatmap spacing values with shared constants so future tile-size changes do not reintroduce misalignment.

## Iteration 76: Hide weekday y-axis in secondary-window heatmap
- **Secondary context clarity**: In `UsageHistoryTabView`, the heatmap weekday y-axis (Sun/Tue/Thu/Sat) is now shown only for primary-window panels.
- **Requested UX behavior**: Secondary-window panels no longer render weekday y-axis labels, reducing semantic mismatch when users interpret secondary data in reset-cycle context.
- **Regression coverage**: Added `UsageHistoryTabViewTests.testShowsWeekdayAxisOnlyForPrimaryWindow` to lock the axis-visibility rule (`primary` shows axis, `secondary` hides axis).
