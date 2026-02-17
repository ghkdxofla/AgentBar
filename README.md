# AgentBar

<p align="center">
  <img src="docs/assets/agentbar-icon.svg" alt="AgentBar icon" width="220" height="220" />
</p>

[![Apple Notarized](https://img.shields.io/badge/Apple-Notarized-000000?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
[![Coverage](https://img.shields.io/badge/coverage-59.6%25-yellow)](#test--coverage)

AgentBar is a macOS menu bar app that tracks AI coding assistant usage in one place.

<p align="center">
  <img src="docs/assets/screenshot.png" alt="AgentBar Screenshot" />
</p>

## What It Does

- Shows current usage in the menu bar and detailed metrics in a popover.
- Supports Claude Code, OpenAI Codex, Google Gemini, GitHub Copilot, Cursor, and Z.ai.
- Includes configurable desktop notifications (Codex watcher + Claude/OpenCode hooks).

## How Usage Is Collected

- Claude Code: Anthropic OAuth usage API (credential read from local Keychain).
- OpenAI Codex: local session logs in `~/.codex/sessions` (JSONL parsing).
- Google Gemini: local logs in `~/.gemini/tmp/**/logs.json`.
- GitHub Copilot: GitHub Copilot API (`gh auth token` first, optional PAT fallback).
- Cursor: Cursor local DB token + Cursor usage API.
- Z.ai: Z.ai quota API with API key from Keychain.

## Settings Menu

- Usage tab: launch at login, refresh interval, per-service enable/disable.
- Usage tab: plan/limit controls and API key/PAT save (service-dependent).
- Notifications tab: notification on/off, event categories, source toggles, message preview.
- Notifications tab: hook status check and sound pack configuration.

## Test / Coverage

- Test command: `xcodebuild test -project AgentBar.xcodeproj -scheme AgentBar -destination 'platform=macOS'`
- Latest local result: `213 tests, 0 failures`
- Coverage report command: `xcrun xccov view --report <path-to-xcresult>`

## Support

[![GitHub Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?style=for-the-badge&logo=github-sponsors)](https://github.com/sponsors/scari)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-%E2%98%95-orange?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/_scari)

## License

MIT License. See [LICENSE](LICENSE).
