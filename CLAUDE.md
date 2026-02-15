# CCUsageBar - Project Instructions

macOS menu bar app (Swift 6.0, macOS 13.0+) showing usage metrics for Claude Code, OpenAI Codex, Google Gemini, GitHub Copilot, Cursor, Z.ai.

## Language

User communicates in Korean. Respond in Korean for conversation, English for code/commits/docs.

## Workflow Rules

### Every change MUST follow this sequence:
1. **Implement** the change
2. **Build & test**: `xcodebuild test -project CCUsageBar.xcodeproj -scheme CCUsageBar -destination 'platform=macOS'` — all tests must pass
3. **Visual smoke test**: Run `/build-run` skill to build and relaunch the app. Verify that the popover opens correctly, all existing UI elements (header with gear icon, service rows, footer with "Last updated" and Quit button) are visible and not clipped.
4. **Update DEVLOG.md**: Add a new `## Iteration N:` entry describing what changed and why. Include "All N tests passing" at the end.
5. **Commit**: Use conventional commit style (`feat:`, `fix:`, `refactor:`, etc.). Never skip commit or doc update unless explicitly told to.

### Regression prevention:
- When adding new items to a list/collection (services, settings sections, etc.), always check that container views have sufficient space (popover height, settings form height, scroll support)
- Never change a fixed-size frame without verifying all content still fits
- If a UI container can grow (e.g., service list), use `ScrollView` so future additions don't break layout

### Commit message format:
```
feat: short summary of the change

Longer explanation of what and why (2-3 lines max).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

### DEVLOG.md format:
```markdown
## Iteration N: Short title
- **Bold key change**: Description of what changed and why
- **Another change**: Details including model/struct/field names
- All N tests passing
```

## Build & Run

- **Build + Run**: `/build-run` skill (builds Debug, kills existing process, launches new build)
- Build only: `xcodebuild build -project CCUsageBar.xcodeproj -scheme CCUsageBar -configuration Debug -derivedDataPath build -quiet`
- Test: `xcodebuild test -project CCUsageBar.xcodeproj -scheme CCUsageBar -destination 'platform=macOS'`
- DMG: `hdiutil create -volname CCUsageBar -srcfolder build/Build/Products/Release/CCUsageBar.app -ov -format UDZO CCUsageBar.dmg`

## Architecture

```
CCUsageBar/
  Models/          ServiceType, UsageData, UsageMetric, SubscriptionPlan
  Services/        UsageProviderProtocol + per-service providers (Claude, Codex, Gemini, Copilot, Cursor, Zai)
  ViewModels/      UsageViewModel (@MainActor, parallel TaskGroup fetch)
  Views/
    StatusBar/     StackedBarView (menu bar icon)
    Popover/       DetailPopoverView, ServiceDetailRow, MetricRow, MiniBarView
    Settings/      SettingsView, SettingsWindowController
  Networking/      APIClient, APIError
  Infrastructure/  KeychainManager, LoginItemManager
  Utilities/       DateUtils, JSONLParser
CCUsageBarTests/   Unit tests per provider + ViewModel + utilities
```

## Provider Details

| Service | Data Source | Unit | Notes |
|---------|-----------|------|-------|
| Claude Code | Anthropic OAuth API (`/api/oauth/usage`) | percent | Token from macOS Keychain "Claude Code-credentials" |
| OpenAI Codex | Local JSONL (`~/.codex/sessions/`) | tokens | rate_limits.primary (5h) / secondary (7d) |
| Google Gemini | Local logs (`~/.gemini/tmp/`) | requests | Daily window only, weeklyUsage=nil |
| GitHub Copilot | GitHub API (`/copilot_internal/user`) | requests | PAT from Keychain, monthly premium requests, weeklyUsage=nil |
| Cursor | Cursor API (`/api/usage`) + local SQLite | requests | JWT from `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, weeklyUsage=nil |
| Z.ai | REST API (`/api/monitor/usage/quota/limit`) | percent (5h) / requests (MCP) | TOKENS_LIMIT=5h, TIME_LIMIT=monthly MCP |

## Key Conventions

- Swift 6 strict concurrency: all models are `Sendable`, providers are `@unchecked Sendable`
- `weeklyUsage` is optional (`UsageMetric?`) — services with a single window set it to nil
- `UsageUnit` has `.tokens`, `.requests`, `.dollars`, `.percent` — MetricRow renders differently for each
- When a provider fetch fails, ViewModel returns zero-usage data (bar stays visible)
- Service display order: Claude, Codex, Gemini, Copilot, Cursor, Z.ai
- API keys stored in Keychain via `KeychainManager` (service: "com.agentbar.apikeys")
- External data/claims should be fact-checked against actual API responses before implementing
