# AgentBar - LLM Agent 사용량 메뉴바 앱 상세 설계 문서

## 1. 개요

### 1.1 목적
Claude Code, OpenAI Codex, Z.ai Coding Plan 3가지 LLM 에이전트 구독 서비스의 실시간 사용량을 macOS 메뉴바에 컴팩트한 막대 그래프로 표시하는 앱.

### 1.2 핵심 기능
- 메뉴바에 최대 3개의 수직 스택 막대 그래프 표시 (각 서비스 1줄)
- 각 막대에 5시간 사용량과 주간 사용량을 색상으로 구분하여 표시
- 마우스 오버 시 상세 정보 팝오버 표시
- 데이터 없는 서비스는 자동 숨김
- 로그인 시 자동 실행 (설정에서 on/off)

### 1.3 기술 스택
| 항목 | 선택 | 이유 |
|------|------|------|
| 언어 | Swift 5.9+ | macOS 네이티브, 성능 |
| UI 프레임워크 | SwiftUI + AppKit 하이브리드 | MenuBarExtra 한계로 커스텀 뷰 필요 |
| 최소 지원 OS | macOS 13.0 (Ventura) | SMAppService, MenuBarExtra 지원 |
| 빌드 시스템 | Xcode 15+ / Swift Package Manager | 표준 macOS 개발 환경 |
| 네트워크 | URLSession (async/await) | 시스템 내장, 추가 의존성 없음 |
| 보안 저장소 | Keychain Services | API 키 안전 보관 |
| 설정 저장 | UserDefaults (@AppStorage) | 간단한 설정값 |

---

## 2. 아키텍처

### 2.1 전체 구조

```
┌─────────────────────────────────────────────────────────────┐
│                        AgentBar.app                         │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐│
│  │  App      │  │  StatusBar   │  │   Settings Window      ││
│  │  Entry    │──│  Controller  │  │   (SwiftUI)            ││
│  │  Point    │  │  (AppKit)    │  └────────────────────────┘│
│  └──────────┘  └──────┬───────┘                             │
│                       │                                      │
│              ┌────────┴────────┐                             │
│              │  UsageViewModel │  @MainActor                 │
│              │  (ObservableObj)│                              │
│              └────────┬────────┘                             │
│                       │                                      │
│    ┌──────────────────┼──────────────────┐                   │
│    │                  │                  │                    │
│    ▼                  ▼                  ▼                    │
│ ┌──────────┐  ┌──────────────┐  ┌──────────────┐           │
│ │ Claude   │  │ OpenAI Codex │  │ Z.ai         │           │
│ │ Provider │  │ Provider     │  │ Provider     │           │
│ └────┬─────┘  └──────┬───────┘  └──────┬───────┘           │
│      │               │                  │                    │
│      ▼               ▼                  ▼                    │
│ ┌──────────┐  ┌──────────────┐  ┌──────────────┐           │
│ │ Local    │  │ OpenAI       │  │ Z.ai         │           │
│ │ JSONL    │  │ Usage API    │  │ Quota API    │           │
│ │ Parser   │  │ Client       │  │ Client       │           │
│ └──────────┘  └──────────────┘  └──────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 레이어 구조

```
┌─────────────────────────────────────────┐
│         Presentation Layer              │
│  StatusBarView, PopoverView, Settings   │
├─────────────────────────────────────────┤
│         ViewModel Layer                 │
│  UsageViewModel (상태 관리 + 타이머)      │
├─────────────────────────────────────────┤
│         Service Layer                   │
│  UsageProviderProtocol 구현체들           │
├─────────────────────────────────────────┤
│         Data Layer                      │
│  API Clients, Local File Parsers        │
├─────────────────────────────────────────┤
│         Infrastructure                  │
│  KeychainManager, SettingsManager       │
└─────────────────────────────────────────┘
```

### 2.3 디렉터리 구조

```
AgentBar/
├── AgentBarApp.swift              # @main 진입점
├── AppDelegate.swift              # NSApplicationDelegate
├── Info.plist                     # LSUIElement=true
│
├── Models/
│   ├── UsageData.swift            # 서비스별 사용량 데이터 모델
│   ├── ServiceType.swift          # enum: claude, codex, zai
│   └── UsageWindow.swift          # enum: fiveHour, weekly
│
├── ViewModels/
│   └── UsageViewModel.swift       # 메인 상태 관리
│
├── Views/
│   ├── StatusBar/
│   │   ├── StatusBarController.swift   # NSStatusItem 관리 (AppKit)
│   │   └── StackedBarView.swift        # 메뉴바 막대 그래프 (SwiftUI)
│   ├── Popover/
│   │   ├── PopoverController.swift     # NSPopover + hover 처리
│   │   └── DetailPopoverView.swift     # 상세 정보 뷰 (SwiftUI)
│   └── Settings/
│       └── SettingsView.swift          # 설정 창 (SwiftUI)
│
├── Services/
│   ├── UsageProviderProtocol.swift     # 프로바이더 인터페이스
│   ├── ClaudeUsageProvider.swift       # Claude Code 데이터 수집
│   ├── CodexUsageProvider.swift        # OpenAI Codex 데이터 수집
│   └── ZaiUsageProvider.swift          # Z.ai 데이터 수집
│
├── Networking/
│   ├── APIClient.swift                 # URLSession 기반 HTTP 클라이언트
│   └── APIError.swift                  # 네트워크 에러 타입
│
├── Infrastructure/
│   ├── KeychainManager.swift           # API 키 보안 저장
│   ├── SettingsManager.swift           # UserDefaults 래퍼
│   └── LoginItemManager.swift          # SMAppService 래퍼
│
├── Utilities/
│   ├── JSONLParser.swift               # JSONL 파일 파서
│   └── DateUtils.swift                 # 5시간/주간 윈도우 계산
│
└── Tests/
    ├── UsageViewModelTests.swift
    ├── ClaudeUsageProviderTests.swift
    ├── CodexUsageProviderTests.swift
    ├── ZaiUsageProviderTests.swift
    ├── JSONLParserTests.swift
    ├── DateUtilsTests.swift
    └── Mocks/
        ├── MockUsageProvider.swift
        └── MockAPIClient.swift
```

---

## 3. 데이터 모델

### 3.1 핵심 모델

```swift
/// 서비스 종류
enum ServiceType: String, CaseIterable, Codable {
    case claude = "Claude Code"
    case codex  = "OpenAI Codex"
    case zai    = "Z.ai GLM"
}

/// 사용량 시간 윈도우
enum UsageWindow {
    case fiveHour   // 5시간 롤링 윈도우
    case weekly     // 7일 주간 윈도우
}

/// 단일 서비스의 사용량 데이터
struct UsageData: Identifiable {
    let id = UUID()
    let service: ServiceType
    let fiveHourUsage: UsageMetric    // 5시간 사용량
    let weeklyUsage: UsageMetric      // 주간 사용량
    let lastUpdated: Date
    let isAvailable: Bool             // 데이터 수집 가능 여부
}

/// 사용량 측정값 (비율 기반)
struct UsageMetric {
    let used: Double        // 사용한 양 (토큰 수 또는 요청 수)
    let total: Double       // 전체 할당량
    var percentage: Double { // 사용 비율 0.0~1.0
        guard total > 0 else { return 0 }
        return min(used / total, 1.0)
    }
    let unit: UsageUnit     // 측정 단위
    let resetTime: Date?    // 다음 리셋 시각
}

/// 측정 단위
enum UsageUnit: String {
    case tokens = "tokens"
    case requests = "requests"
    case dollars = "USD"
}
```

### 3.2 설정 모델

```swift
/// 앱 설정
struct AppSettings {
    var refreshInterval: TimeInterval = 60       // 갱신 주기 (초)
    var launchAtLogin: Bool = false               // 로그인 시 자동 실행
    var enabledServices: Set<ServiceType> = Set(ServiceType.allCases)
    var showPercentageText: Bool = false          // 막대 위 퍼센트 표시
}
```

---

## 4. 각 서비스별 데이터 수집 상세

### 4.1 Claude Code — 로컬 파일 파싱

#### Under the Hood: Claude Code의 사용량 기록 방식

Claude Code는 모든 대화 기록을 로컬 JSONL 파일에 저장한다. 각 API 호출의 토큰 사용량이 메시지 단위로 기록되며, 이 파일들을 파싱하여 사용량을 산출한다.

```
~/.claude/
├── stats-cache.json                          # 집계된 통계 캐시
├── history.jsonl                             # 대화 이력 메타데이터
└── projects/
    └── {base64-encoded-project-path}/
        └── {session-id}.jsonl                # 세션별 상세 대화 기록
```

#### 데이터 수집 흐름

```
┌─────────────────────────────────────────────────────────┐
│                 ClaudeUsageProvider                       │
│                                                          │
│  1. ~/.claude/projects/ 하위 JSONL 파일 스캔              │
│     └─ FileManager로 디렉터리 순회                        │
│     └─ 파일 수정일 기준 최근 7일 이내 파일만 대상           │
│                                                          │
│  2. JSONL 파싱 (줄 단위 JSON 디코딩)                      │
│     └─ 각 줄: {"type":"assistant","message":{...},        │
│               "costUSD":0.05, "usage":{                   │
│                 "input_tokens":1000,                      │
│                 "output_tokens":500,                      │
│                 "cache_read_input_tokens":5000,           │
│                 "cache_creation_input_tokens":200         │
│               }, "timestamp":"2026-02-14T10:30:00Z"}      │
│                                                          │
│  3. 시간 윈도우별 집계                                     │
│     └─ 5시간: now - 5h ~ now 범위 메시지 토큰 합산         │
│     └─ 주간: now - 7d ~ now 범위 메시지 토큰 합산          │
│                                                          │
│  4. 총 할당량 대비 비율 계산                               │
│     └─ Max 플랜 기준 추정값 사용 (설정에서 수동 지정 가능)  │
└─────────────────────────────────────────────────────────┘
```

#### JSONL 파서 상세

```swift
/// JSONL 파일의 메시지 레코드
struct ClaudeMessageRecord: Decodable {
    let type: String              // "user" | "assistant" | "system"
    let timestamp: String?        // ISO 8601
    let costUSD: Double?
    let usage: ClaudeTokenUsage?
    let model: String?            // "claude-opus-4-6" 등
}

struct ClaudeTokenUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?

    var totalTokens: Int {
        (input_tokens ?? 0) +
        (output_tokens ?? 0) +
        (cache_read_input_tokens ?? 0) +
        (cache_creation_input_tokens ?? 0)
    }
}
```

#### 5시간 윈도우 계산 로직

Claude Code의 과금은 5시간 롤링 윈도우 기반이다. 이 앱에서는 현재 시각으로부터 정확히 5시간 전까지의 누적 사용량을 계산한다.

```swift
func calculateFiveHourUsage(records: [ClaudeMessageRecord]) -> UsageMetric {
    let fiveHoursAgo = Date().addingTimeInterval(-5 * 3600)
    let recentRecords = records.filter { record in
        guard let ts = record.timestamp,
              let date = ISO8601DateFormatter().date(from: ts) else { return false }
        return date >= fiveHoursAgo
    }
    let totalTokens = recentRecords.compactMap(\.usage?.totalTokens).reduce(0, +)
    let totalCost = recentRecords.compactMap(\.costUSD).reduce(0, +)

    // Max 플랜 5시간 추정 한도 (사용자 설정 가능)
    let fiveHourLimit: Double = settings.claudeFiveHourTokenLimit

    return UsageMetric(
        used: Double(totalTokens),
        total: fiveHourLimit,
        unit: .tokens,
        resetTime: fiveHoursAgo.addingTimeInterval(5 * 3600)
    )
}
```

#### 대안: stats-cache.json 활용

`stats-cache.json`은 Claude Code가 자체적으로 집계한 캐시 데이터를 담고 있다. JSONL 파싱보다 빠르지만, 5시간 윈도우 단위의 세분화된 데이터는 제공하지 않는다. 따라서:

- **빠른 표시 (앱 시작 시)**: `stats-cache.json`에서 오늘 일일 사용량을 먼저 로드
- **정확한 계산 (백그라운드)**: JSONL 파일을 비동기 파싱하여 5시간/주간 정확한 값 산출
- 두 결과를 merge하여 최종 표시

#### 알려진 제약

| 제약 | 설명 | 대응 |
|------|------|------|
| 할당량 한도 미공개 | Anthropic이 Max 플랜의 정확한 토큰 한도를 공개하지 않음 | 사용자가 설정에서 수동 입력, 또는 커뮤니티 추정값 기본 제공 |
| 파일 크기 | 장기 사용 시 JSONL 파일이 수백 MB에 달할 수 있음 | 최근 7일 파일만 스캔, 역방향 읽기(tail)로 최적화 |
| stats-cache 비공식 | stats-cache.json 형식이 버전업에 따라 변경될 수 있음 | 디코딩 실패 시 graceful fallback |

---

### 4.2 OpenAI Codex — Usage API

#### Under the Hood: OpenAI의 사용량 추적 방식

OpenAI는 조직 단위의 Usage API를 제공한다. API 키로 인증하여 일 단위 버킷의 토큰 사용량과 비용을 조회할 수 있다. Codex CLI도 로컬에 세션 기록을 남기므로 두 소스를 병행한다.

#### API 엔드포인트

```
# 비용 조회 (일 단위)
GET https://api.openai.com/v1/organization/costs
  ?start_time={unix_timestamp}
  &bucket_width=1d
  &limit=7

# 토큰 사용량 조회
GET https://api.openai.com/v1/organization/usage/completions
  ?start_time={unix_timestamp}
  &bucket_width=1d
  &limit=7

Headers:
  Authorization: Bearer {OPENAI_API_KEY}
  Content-Type: application/json
```

#### API 응답 구조

```json
// GET /v1/organization/costs
{
  "object": "page",
  "data": [
    {
      "object": "bucket",
      "start_time": 1739404800,
      "end_time": 1739491200,
      "results": [
        {
          "object": "organization.costs.result",
          "amount": { "value": 2.35, "currency": "usd" },
          "line_item": "codex-mini-latest",
          "project_id": "proj_abc123"
        }
      ]
    }
  ],
  "has_more": false,
  "next_page": null
}

// GET /v1/organization/usage/completions
{
  "object": "page",
  "data": [
    {
      "object": "bucket",
      "start_time": 1739404800,
      "end_time": 1739491200,
      "results": [
        {
          "object": "organization.usage.completions.result",
          "input_tokens": 45000,
          "output_tokens": 12000,
          "num_model_requests": 85,
          "model": "codex-mini-latest"
        }
      ]
    }
  ]
}
```

#### 데이터 수집 흐름

```
┌─────────────────────────────────────────────────────────┐
│                 CodexUsageProvider                        │
│                                                          │
│  [Primary] OpenAI Usage API                              │
│  1. Keychain에서 OPENAI_API_KEY 로드                      │
│  2. /v1/organization/usage/completions 호출               │
│     └─ start_time: 7일 전 Unix timestamp                 │
│     └─ bucket_width: 1d                                  │
│  3. 일별 버킷 데이터를 5시간/주간으로 집계                  │
│     └─ 5시간: API가 최소 1d 단위이므로 로컬 보완 필요       │
│     └─ 주간: 최근 7일 버킷 합산                           │
│                                                          │
│  [Secondary] 로컬 세션 파일 (~/.codex/)                   │
│  4. ~/.codex/sessions/ 디렉터리의 JSONL 파일 파싱          │
│     └─ 5시간 윈도우 정밀 계산에 활용                       │
│  5. API 결과 + 로컬 결과를 merge                          │
│                                                          │
│  [Fallback] API 실패 시 로컬 데이터만 사용                 │
└─────────────────────────────────────────────────────────┘
```

#### 5시간 윈도우 처리

OpenAI Usage API는 최소 `1d` (일 단위) 버킷만 지원한다. 5시간 단위 정밀 측정을 위해:

1. **로컬 세션 파일 우선**: `~/.codex/sessions/` 의 JSONL을 파싱하여 최근 5시간 토큰 계산
2. **API 보완**: 오늘 일자 버킷 값을 참고하여 cross-check
3. **로컬 파일 없을 시**: 당일 API 값을 표시하되, "일 단위 (근사치)" 라벨 표시

#### 알려진 제약

| 제약 | 설명 | 대응 |
|------|------|------|
| API 최소 1d 버킷 | 5시간 단위 조회 불가 | 로컬 JSONL 파싱으로 보완 |
| API 키 권한 | 조직 Usage API 접근에 admin/owner 역할 필요할 수 있음 | 설정에서 안내 메시지, 로컬 fallback |
| 데이터 지연 | API 데이터 ~5분 딜레이 | UI에 "last updated" 시각 표시 |
| Codex 롤링 한도 미공개 | Pro/Plus 플랜의 정확한 5시간 한도 미공개 | 사용자 수동 입력 또는 커뮤니티 추정값 |

---

### 4.3 Z.ai Coding Plan — Quota API

#### Under the Hood: Z.ai의 쿼터 관리 방식

Z.ai는 Coding Plan 구독자에게 5시간 주기와 7일 주기의 이중 쿼터 시스템을 적용한다. 전용 Quota API가 있어 실시간으로 잔여 쿼터를 조회할 수 있으며, 3개 서비스 중 가장 정확한 데이터를 제공한다.

#### API 엔드포인트

```
# 쿼터 현황 조회
GET https://api.z.ai/api/monitor/usage/quota/limit

Headers:
  Authorization: {ZAI_API_KEY}     # "Bearer" 접두사 없이 전송하는 구현도 있음
  Accept: application/json
  Accept-Language: en-US,en

# 모델별 사용량 (24시간)
GET https://api.z.ai/api/monitor/usage/model-usage
  ?startTime={epoch_ms}&endTime={epoch_ms}

# 도구 사용량
GET https://api.z.ai/api/monitor/usage/tool-usage
  ?startTime={epoch_ms}&endTime={epoch_ms}
```

#### API 응답 구조

```json
// GET /api/monitor/usage/quota/limit
{
  "data": {
    "planName": "GLM Coding Pro",
    "limits": [
      {
        "type": "TOKENS_LIMIT",
        "used": 450000,
        "total": 2000000,
        "nextResetTime": 1739430000000
      },
      {
        "type": "TIME_LIMIT",
        "used": 120,
        "total": 600,
        "nextResetTime": 1739430000000
      }
    ],
    "usageDetails": [
      {
        "model": "glm-5",
        "tokens": 300000,
        "calls": 45
      },
      {
        "model": "glm-4.7",
        "tokens": 150000,
        "calls": 30
      }
    ]
  }
}
```

#### 데이터 수집 흐름

```
┌─────────────────────────────────────────────────────────┐
│                 ZaiUsageProvider                          │
│                                                          │
│  1. Keychain에서 ZAI_API_KEY 로드                         │
│  2. /api/monitor/usage/quota/limit 호출                   │
│  3. 응답에서 직접 used/total 추출                          │
│     └─ TOKENS_LIMIT → 5시간 윈도우 사용량                  │
│     └─ nextResetTime → 리셋 시각                          │
│  4. 주간 사용량은 model-usage API로 7일 집계               │
│  5. UsageData 객체 생성                                   │
│                                                          │
│  ※ Z.ai API가 5시간/주간을 명시적으로 구분하므로            │
│    가장 정확한 데이터 제공                                 │
└─────────────────────────────────────────────────────────┘
```

#### 인증 주의사항

Z.ai API의 인증 방식에 2가지 변형이 존재한다:

```swift
// 방식 1: Bearer 토큰 (공식 문서)
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

// 방식 2: Raw 키 (일부 모니터링 엔드포인트)
request.setValue(apiKey, forHTTPHeaderField: "Authorization")
```

Provider는 Bearer 방식을 먼저 시도하고, 401 응답 시 Raw 방식으로 재시도한다.

#### 알려진 제약

| 제약 | 설명 | 대응 |
|------|------|------|
| Auth 방식 불일치 | 엔드포인트별로 Bearer/Raw 차이 | 자동 재시도 로직 |
| API 키 형식 | `{ID}.{secret}` 형식, 노출 시 교체 불가 | Keychain 필수 |
| 주간 데이터 별도 계산 | quota/limit은 현재 주기만 반환 | model-usage API로 7일 집계 |

---

## 5. UI 설계

### 5.1 메뉴바 막대 그래프

#### 레이아웃

```
 macOS 메뉴바 (높이 22px)
 ┌──────────────────────────────────────────────────────────────┐
 │  ◀ 다른 아이콘들 ...   [AgentBar 영역]    ... 시계 ▶          │
 │                        ┌─────────────┐                       │
 │                        │ ████████░░░ │ ← Claude (6px 높이)   │
 │                        │ █████░░░░░░ │ ← Codex  (6px 높이)   │
 │                        │ ███████░░░░ │ ← Z.ai   (6px 높이)   │
 │                        └─────────────┘                       │
 │                         ↑ 폭 60~80px                         │
 └──────────────────────────────────────────────────────────────┘
```

#### 각 막대의 색상 구분

```
 하나의 막대 (예: Claude)
 ┌──────────────────────────────────────────────────┐
 │ ████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
 │ ▲ 5시간 사용량   ▲ 주간 사용량          ▲ 남은 한도 │
 │ (진한 색)        (연한 색)              (회색 배경)  │
 └──────────────────────────────────────────────────┘
```

- **5시간 사용량**: 서비스 고유 색상의 진한 톤 (예: Claude=진파랑, Codex=진초록, Z.ai=진주황)
- **주간 사용량 (5시간 제외 부분)**: 서비스 고유 색상의 연한 톤
- **남은 한도**: 반투명 회색 배경

#### 색상 팔레트

| 서비스 | 5시간 (진한) | 주간 (연한) | 배경 |
|--------|-------------|-------------|------|
| Claude | `#D97706` (amber-600) | `#FCD34D` (amber-300) | `#37415120` |
| Codex | `#059669` (emerald-600) | `#6EE7B7` (emerald-300) | `#37415120` |
| Z.ai | `#7C3AED` (violet-600) | `#C4B5FD` (violet-300) | `#37415120` |

#### SwiftUI 구현 - 메뉴바 뷰

```swift
struct StackedBarView: View {
    let services: [UsageData]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(services.filter(\.isAvailable)) { data in
                SingleBarView(usage: data)
            }
        }
        .frame(width: 64, height: 20)
        .padding(.horizontal, 2)
    }
}

struct SingleBarView: View {
    let usage: UsageData

    private var barHeight: CGFloat {
        // 서비스 수에 따라 동적 높이 조절
        // 1개: 12px, 2개: 8px, 3개: 5px
        return max(5, 18 / CGFloat(max(1, activeServiceCount)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 배경 (전체 막대)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.2))

                // 주간 사용량 (연한 색)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(usage.service.lightColor)
                    .frame(width: geo.size.width * usage.weeklyUsage.percentage)

                // 5시간 사용량 (진한 색, 주간 위에 겹침)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(usage.service.darkColor)
                    .frame(width: geo.size.width * usage.fiveHourUsage.percentage)
            }
        }
        .frame(height: barHeight)
    }
}
```

### 5.2 마우스 오버 팝오버

#### 레이아웃

```
┌──────────────────────────────────────┐
│  AgentBar                   ⚙️ 설정  │
├──────────────────────────────────────┤
│                                      │
│  ● Claude Code             ━━━━━━━  │
│    5h: 125K / 500K tokens  (25%)     │
│    7d: 2.1M / 10M tokens   (21%)     │
│    리셋: 2h 34m 후                    │
│                                      │
│  ● OpenAI Codex            ━━━━━━━  │
│    5h: $1.25 / $5.00       (25%)     │
│    7d: $12.50 / $50.00     (25%)     │
│    리셋: 3h 12m 후                    │
│                                      │
│  ● Z.ai GLM                ━━━━━━━  │
│    5h: 450K / 2M tokens    (22%)     │
│    7d: 3.2M / 15M tokens   (21%)     │
│    리셋: 1h 05m 후                    │
│                                      │
│  마지막 갱신: 10초 전                  │
├──────────────────────────────────────┤
│  종료                                 │
└──────────────────────────────────────┘
```

#### 팝오버 동작 방식

```
마우스 진입 (mouseEntered)
    │
    ├─ 0.3초 딜레이 타이머 시작
    │  (즉시 표시하면 지나가는 것만으로도 뜸)
    │
    ├─ 0.3초 후 팝오버 표시
    │  └─ NSPopover.show(relativeTo:of:preferredEdge:)
    │  └─ preferredEdge: .minY (아래쪽으로 표시)
    │
    └─ 마우스 이탈 (mouseExited)
       ├─ 딜레이 타이머 취소 (아직 표시 전이면)
       └─ 0.5초 후 팝오버 닫기
          (팝오버 내부에 마우스가 있으면 취소)
```

### 5.3 설정 창

```
┌──────────────────────────────────────────────┐
│  AgentBar 설정                                │
├──────────────────────────────────────────────┤
│                                               │
│  일반                                         │
│  ┌───────────────────────────────────────┐    │
│  │ [✓] 로그인 시 자동 시작                │    │
│  │ 갱신 주기: [60초 ▼]                    │    │
│  └───────────────────────────────────────┘    │
│                                               │
│  서비스                                       │
│  ┌───────────────────────────────────────┐    │
│  │ [✓] Claude Code                       │    │
│  │     5시간 한도: [500000] tokens        │    │
│  │     주간 한도: [10000000] tokens       │    │
│  │                                       │    │
│  │ [✓] OpenAI Codex                      │    │
│  │     API Key: [••••••••••] [변경]       │    │
│  │     5시간 한도: [$5.00]                │    │
│  │     주간 한도: [$50.00]                │    │
│  │                                       │    │
│  │ [✓] Z.ai GLM                          │    │
│  │     API Key: [••••••••••] [변경]       │    │
│  │     (한도는 API에서 자동 조회)          │    │
│  └───────────────────────────────────────┘    │
│                                               │
│  [저장]                       [초기화]         │
└──────────────────────────────────────────────┘
```

---

## 6. Under the Hood — 핵심 동작 메커니즘

### 6.1 앱 생명주기

```
macOS 부팅/로그인
    │
    ├─ SMAppService가 등록된 경우 → 자동 실행
    │
    ▼
AgentBarApp.init()
    │
    ├─ Info.plist: LSUIElement=true → Dock 아이콘 없음
    ├─ AppDelegate.applicationDidFinishLaunching()
    │   ├─ StatusBarController 초기화
    │   │   ├─ NSStatusBar.system.statusItem(withLength: 70) 생성
    │   │   ├─ NSHostingView(rootView: StackedBarView) → button.addSubview()
    │   │   └─ NSTrackingArea 설정 (마우스 hover 감지)
    │   │
    │   └─ UsageViewModel 초기화
    │       ├─ 3개 Provider 생성 (Claude, Codex, Z.ai)
    │       ├─ Keychain에서 API 키 로드
    │       └─ Timer.publish(every: refreshInterval) 시작
    │
    ▼
[이벤트 루프 진입 - 메뉴바 표시 상태]
    │
    ├─ 매 refreshInterval(기본 60초)마다:
    │   └─ fetchAllUsage() → 3개 Provider 병렬 호출
    │       ├─ TaskGroup으로 병렬 실행
    │       ├─ 각 Provider: 데이터 수집 → UsageData 반환
    │       ├─ 실패 시: 해당 서비스 isAvailable=false
    │       └─ @Published usageData 업데이트 → UI 자동 갱신
    │
    ├─ 마우스 hover 시:
    │   ├─ mouseEntered → 0.3초 딜레이 → NSPopover 표시
    │   └─ mouseExited → 0.5초 딜레이 → NSPopover 닫기
    │
    └─ 앱 종료:
        └─ NSApp.terminate() → Timer 정리, 리소스 해제
```

### 6.2 데이터 갱신 파이프라인

```
Timer fires (매 60초)
    │
    ▼
UsageViewModel.fetchAllUsage()
    │
    ├─ withTaskGroup(of: UsageData?.self) { group in
    │      group.addTask { await claudeProvider.fetch() }
    │      group.addTask { await codexProvider.fetch() }
    │      group.addTask { await zaiProvider.fetch() }
    │  }
    │
    ├─ 각 Provider 내부:
    │   ┌─────────────────────────────────┐
    │   │ [Claude] 로컬 파일 I/O          │
    │   │  FileManager.default            │
    │   │  .contentsOfDirectory()         │
    │   │  → JSONL 스트리밍 파싱           │
    │   │  → 시간 필터 + 토큰 집계         │
    │   └─────────────────────────────────┘
    │   ┌─────────────────────────────────┐
    │   │ [Codex] HTTP API 호출           │
    │   │  URLSession.shared              │
    │   │  .data(for: request)            │
    │   │  → JSON 디코딩                   │
    │   │  + 로컬 JSONL 보완              │
    │   └─────────────────────────────────┘
    │   ┌─────────────────────────────────┐
    │   │ [Z.ai] HTTP API 호출            │
    │   │  URLSession.shared              │
    │   │  .data(for: request)            │
    │   │  → JSON 디코딩                   │
    │   │  → used/total 직접 추출          │
    │   └─────────────────────────────────┘
    │
    ▼
@Published var usageData: [UsageData]  업데이트
    │
    ▼
SwiftUI 뷰 자동 갱신 (@ObservedObject)
    ├─ StackedBarView 리드로우 (메뉴바)
    └─ DetailPopoverView 리드로우 (열려있는 경우)
```

### 6.3 NSStatusItem + 커스텀 뷰 렌더링 메커니즘

MenuBarExtra의 `.window` 스타일은 팝오버에만 커스텀 뷰를 허용하고, 메뉴바 아이콘 자체는 SF Symbol이나 텍스트로 제한된다. 따라서 막대 그래프를 메뉴바에 직접 그리려면 AppKit의 `NSStatusItem`을 직접 다룬다.

```swift
class StatusBarController {
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<StackedBarView>?
    private var popoverController: PopoverController?

    func setup(viewModel: UsageViewModel) {
        // 1. 상태 아이템 생성 (고정 폭)
        statusItem = NSStatusBar.system.statusItem(withLength: 70)

        guard let button = statusItem?.button else { return }

        // 2. SwiftUI 뷰를 NSHostingView로 래핑
        let barView = StackedBarView(services: viewModel.usageData)
        hostingView = NSHostingView(rootView: barView)
        hostingView?.frame = NSRect(x: 0, y: 0, width: 64, height: 22)

        // 3. 버튼에 커스텀 뷰 삽입
        button.frame = NSRect(x: 0, y: 0, width: 70, height: 22)
        button.addSubview(hostingView!)

        // 4. hover 감지용 TrackingArea 설정
        let trackingArea = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)

        // 5. PopoverController 준비
        popoverController = PopoverController(
            statusItem: statusItem!,
            viewModel: viewModel
        )
    }

    /// 뷰 모델 변경 시 호출 — SwiftUI 바인딩으로 자동 처리됨
    func updateBarView(with data: [UsageData]) {
        hostingView?.rootView = StackedBarView(services: data)
    }
}
```

### 6.4 Hover 팝오버 동작 상세

macOS 메뉴바 아이템은 기본적으로 click 이벤트만 처리한다. Hover를 구현하기 위해 `NSTrackingArea`를 사용한다.

```swift
class PopoverController: NSObject {
    private var popover: NSPopover?
    private var statusItem: NSStatusItem
    private var showTimer: Timer?
    private var hideTimer: Timer?
    private var isMouseInsidePopover = false

    // mouseEntered → 0.3초 후 표시
    override func mouseEntered(with event: NSEvent) {
        hideTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) {
            [weak self] _ in
            self?.showPopover()
        }
    }

    // mouseExited → 0.5초 후 닫기 (팝오버 내부가 아니면)
    override func mouseExited(with event: NSEvent) {
        showTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {
            [weak self] _ in
            guard let self, !self.isMouseInsidePopover else { return }
            self.hidePopover()
        }
    }

    private func showPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 350)
        popover.behavior = .transient   // 다른 곳 클릭 시 자동 닫힘
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DetailPopoverView(viewModel: viewModel)
        )

        // 팝오버 내부 마우스 추적
        popover.contentViewController?.view.addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        self.popover = popover
    }
}
```

### 6.5 Login Item 등록 메커니즘

```swift
import ServiceManagement

class LoginItemManager {
    /// 현재 등록 상태 (시스템에서 직접 조회)
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            // 시스템에 로그인 아이템 등록
            // → 시스템 설정 > 일반 > 로그인 항목에 표시됨
            // → 사용자에게 알림 표시 (최초 1회)
            try SMAppService.mainApp.register()
        } else {
            // 등록 해제
            try SMAppService.mainApp.unregister()
        }
    }
}
```

**내부 동작**: `SMAppService.mainApp.register()` 호출 시 macOS는 앱의 번들 ID를 `/Library/LaunchAgents/` 또는 `~/Library/LaunchAgents/`에 등록한다. 이후 사용자 로그인 시 launchd가 자동으로 앱을 실행한다.

### 6.6 Keychain을 통한 API 키 보안 저장

```swift
class KeychainManager {
    private static let service = "com.agentbar.apikeys"

    static func save(key: String, account: String) throws {
        let data = key.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,   // "openai" 또는 "zai"
            kSecValueData as String:   data
        ]
        // 기존 항목 삭제 후 추가
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
```

**왜 Keychain인가?**
- `UserDefaults`는 `~/Library/Preferences/`에 플레인텍스트 plist로 저장 → API 키 노출 위험
- Keychain은 macOS의 암호화된 저장소에 보관
- 앱이 삭제되어도 Keychain 데이터는 유지 (사용자 명시적 삭제 필요)

### 6.7 에러 처리 및 Resilience

```
┌──────────────────────────────────────────────────┐
│              에러 처리 전략                         │
├──────────────────────────────────────────────────┤
│                                                   │
│  네트워크 에러 (Codex, Z.ai API):                  │
│  ├─ 타임아웃 (10초): 다음 주기에 재시도              │
│  ├─ 401 Unauthorized: 설정에서 API 키 확인 안내     │
│  ├─ 429 Rate Limited: 지수 백오프 (2x 간격)         │
│  ├─ 5xx 서버 에러: 다음 주기에 재시도               │
│  └─ 연속 3회 실패: 해당 서비스 상태를 "오류"로 표시  │
│                                                   │
│  로컬 파일 에러 (Claude):                          │
│  ├─ 파일 없음: isAvailable=false, 막대 숨김         │
│  ├─ 파싱 에러: 해당 줄 건너뛰기 (partial success)   │
│  ├─ 권한 없음: 설정에서 파일 접근 권한 안내          │
│  └─ 파일 잠김: 0.5초 후 재시도 (최대 3회)           │
│                                                   │
│  전체 실패 시:                                     │
│  ├─ 메뉴바에 ⚠️ 아이콘 표시                        │
│  ├─ 팝오버에 에러 메시지와 마지막 성공 데이터         │
│  └─ 타이머는 계속 동작 (자동 복구 시도)              │
└──────────────────────────────────────────────────┘
```

### 6.8 메모리 및 성능 최적화

| 항목 | 전략 | 이유 |
|------|------|------|
| JSONL 파싱 | 스트리밍 라인 리더 (전체 로드 X) | 수백 MB 파일 대응 |
| 파일 스캔 범위 | 최근 7일 수정된 파일만 | 불필요한 I/O 방지 |
| API 호출 | TaskGroup 병렬, 10초 타임아웃 | 갱신 주기 내 완료 보장 |
| SwiftUI 뷰 | `EquatableView` 사용, 불필요한 리드로우 방지 | 메뉴바 뷰는 매우 자주 갱신 가능 |
| Timer | RunLoop.main에 등록, 앱 비활성 시에도 동작 | 메뉴바 앱은 항상 "비활성" 상태 |
| 메모리 | 파싱된 레코드는 집계 후 즉시 해제 | 장기 실행 앱의 메모리 누수 방지 |

---

## 7. 프로토콜 및 인터페이스

### 7.1 UsageProviderProtocol

```swift
/// 각 서비스별 데이터 수집기가 구현하는 프로토콜
protocol UsageProviderProtocol: Sendable {
    /// 서비스 종류
    var serviceType: ServiceType { get }

    /// 데이터 수집 가능 여부 (API 키 존재, 로컬 파일 존재 등)
    func isConfigured() async -> Bool

    /// 사용량 데이터 수집
    /// - Returns: 수집된 UsageData, 실패 시 nil
    func fetchUsage() async throws -> UsageData

    /// Provider 검증 (API 키 유효성 등)
    func validate() async throws -> Bool
}
```

### 7.2 APIClient

```swift
/// 공통 HTTP 클라이언트
actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func get<T: Decodable>(
        url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 10
    ) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try decoder.decode(T.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
}
```

---

## 8. 테스트 전략

### 8.1 테스트 계층

```
┌──────────────────────────────────────────────┐
│            E2E Tests (수동)                    │
│   실제 API 키로 전체 흐름 검증                  │
├──────────────────────────────────────────────┤
│          Integration Tests                    │
│   Provider + 실제 파일/Mock API               │
├──────────────────────────────────────────────┤
│            Unit Tests                         │
│   모델, 파서, 뷰모델, 유틸리티                  │
└──────────────────────────────────────────────┘
```

### 8.2 Unit Tests

#### 8.2.1 JSONL 파서 테스트

```swift
class JSONLParserTests: XCTestCase {

    // 정상 파싱
    func testParseValidJSONL() throws {
        let input = """
        {"type":"assistant","timestamp":"2026-02-14T10:00:00Z","usage":{"input_tokens":100,"output_tokens":50},"costUSD":0.01}
        {"type":"user","timestamp":"2026-02-14T10:01:00Z"}
        {"type":"assistant","timestamp":"2026-02-14T10:02:00Z","usage":{"input_tokens":200,"output_tokens":100},"costUSD":0.02}
        """

        let records = try JSONLParser.parse(input, as: ClaudeMessageRecord.self)

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].usage?.input_tokens, 100)
        XCTAssertEqual(records[2].costUSD, 0.02)
    }

    // 부분 파싱 실패 (일부 줄이 깨진 경우)
    func testParsePartiallyCorruptedJSONL() throws {
        let input = """
        {"type":"assistant","usage":{"input_tokens":100}}
        {invalid json line}
        {"type":"assistant","usage":{"input_tokens":200}}
        """

        let records = try JSONLParser.parse(input, as: ClaudeMessageRecord.self)

        // 깨진 줄은 건너뛰고 유효한 2개만 반환
        XCTAssertEqual(records.count, 2)
    }

    // 빈 파일
    func testParseEmptyFile() throws {
        let records = try JSONLParser.parse("", as: ClaudeMessageRecord.self)
        XCTAssertTrue(records.isEmpty)
    }

    // 대용량 파일 스트리밍 파싱
    func testStreamingParsePerformance() throws {
        // 10,000줄 JSONL 생성
        let lines = (0..<10000).map { i in
            """
            {"type":"assistant","timestamp":"2026-02-14T\(String(format:"%02d",i/3600)):\(String(format:"%02d",(i%3600)/60)):00Z","usage":{"input_tokens":\(i*10),"output_tokens":\(i*5)}}
            """
        }
        let tempFile = createTempFile(content: lines.joined(separator: "\n"))

        measure {
            let records = try! JSONLParser.parseFile(tempFile, as: ClaudeMessageRecord.self)
            XCTAssertEqual(records.count, 10000)
        }
    }
}
```

#### 8.2.2 시간 윈도우 계산 테스트

```swift
class DateUtilsTests: XCTestCase {

    func testFiveHourWindowBoundary() {
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let justInside = now.addingTimeInterval(-4 * 3600 - 59 * 60)
        let justOutside = now.addingTimeInterval(-5 * 3600 - 1)

        XCTAssertTrue(DateUtils.isWithinFiveHourWindow(justInside, relativeTo: now))
        XCTAssertTrue(DateUtils.isWithinFiveHourWindow(fiveHoursAgo, relativeTo: now))
        XCTAssertFalse(DateUtils.isWithinFiveHourWindow(justOutside, relativeTo: now))
    }

    func testWeeklyWindowBoundary() {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let justOutside = now.addingTimeInterval(-7 * 24 * 3600 - 1)

        XCTAssertTrue(DateUtils.isWithinWeeklyWindow(sevenDaysAgo, relativeTo: now))
        XCTAssertFalse(DateUtils.isWithinWeeklyWindow(justOutside, relativeTo: now))
    }

    func testResetTimeCalculation() {
        let resetTime = DateUtils.nextResetTime(
            from: Date(),
            windowDuration: 5 * 3600  // 5시간
        )
        let diff = resetTime.timeIntervalSinceNow
        XCTAssertTrue(diff > 0 && diff <= 5 * 3600)
    }
}
```

#### 8.2.3 UsageViewModel 테스트

```swift
class UsageViewModelTests: XCTestCase {

    func testFetchAllUsageParallel() async {
        let mockClaude = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )
        let mockCodex = MockUsageProvider(
            serviceType: .codex,
            result: .success(UsageData.mock(service: .codex))
        )
        let mockZai = MockUsageProvider(
            serviceType: .zai,
            result: .failure(APIError.unauthorized)
        )

        let vm = UsageViewModel(providers: [mockClaude, mockCodex, mockZai])

        await vm.fetchAllUsage()

        // Claude + Codex 성공, Z.ai 실패
        XCTAssertEqual(vm.usageData.count, 2)
        XCTAssertTrue(vm.usageData.allSatisfy(\.isAvailable))
        XCTAssertNil(vm.usageData.first(where: { $0.service == .zai }))
    }

    func testProviderFailureDoesNotAffectOthers() async {
        let slowProvider = MockUsageProvider(
            serviceType: .codex,
            result: .failure(APIError.timeout),
            delay: 5.0  // 5초 지연
        )
        let fastProvider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude)),
            delay: 0.1
        )

        let vm = UsageViewModel(
            providers: [slowProvider, fastProvider],
            timeout: 3.0  // 3초 타임아웃
        )

        await vm.fetchAllUsage()

        // Claude는 성공, Codex는 타임아웃
        XCTAssertEqual(vm.usageData.count, 1)
        XCTAssertEqual(vm.usageData.first?.service, .claude)
    }

    func testTimerFiresAtInterval() async throws {
        let provider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )
        let vm = UsageViewModel(
            providers: [provider],
            refreshInterval: 0.5  // 0.5초 (테스트용)
        )

        vm.startMonitoring()

        try await Task.sleep(for: .seconds(1.2))

        // 0.5초 간격 → 1.2초 동안 최소 2회 호출
        XCTAssertGreaterThanOrEqual(provider.fetchCount, 2)

        vm.stopMonitoring()
    }
}
```

#### 8.2.4 각 Provider 테스트

```swift
// Claude Provider: 로컬 파일 파싱 테스트
class ClaudeUsageProviderTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testParsesRecentSessionFiles() async throws {
        // 테스트용 JSONL 파일 생성
        let sessionFile = tempDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"type":"assistant","timestamp":"\(now)","usage":{"input_tokens":1000,"output_tokens":500},"costUSD":0.05}
        {"type":"assistant","timestamp":"\(now)","usage":{"input_tokens":2000,"output_tokens":800},"costUSD":0.08}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .claude)
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(usage.fiveHourUsage.used, 4300)  // 1000+500+2000+800
    }

    func testIgnoresOldFiles() async throws {
        // 8일 전 파일 (수정일 조작)
        let oldFile = tempDir.appendingPathComponent("old_session.jsonl")
        try "{}".write(to: oldFile, atomically: true, encoding: .utf8)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        try FileManager.default.setAttributes(
            [.modificationDate: eightDaysAgo],
            ofItemAtPath: oldFile.path
        )

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // 8일 전 파일은 무시되어 0
        XCTAssertEqual(usage.fiveHourUsage.used, 0)
    }

    func testHandlesMissingDirectory() async {
        let provider = ClaudeUsageProvider(
            projectsDir: URL(fileURLWithPath: "/nonexistent/path")
        )

        let isConfigured = await provider.isConfigured()
        XCTAssertFalse(isConfigured)
    }
}

// Z.ai Provider: API 응답 파싱 테스트
class ZaiUsageProviderTests: XCTestCase {

    func testParsesQuotaResponse() async throws {
        let mockJSON = """
        {
          "data": {
            "planName": "GLM Coding Pro",
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "used": 450000,
                "total": 2000000,
                "nextResetTime": \(Int(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000))
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let mockClient = MockAPIClient(responseData: mockJSON)
        let provider = ZaiUsageProvider(apiClient: mockClient)

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.fiveHourUsage.used, 450000)
        XCTAssertEqual(usage.fiveHourUsage.total, 2000000)
        XCTAssertEqual(usage.fiveHourUsage.percentage, 0.225, accuracy: 0.001)
    }

    func testHandlesAuthRetry() async throws {
        // 첫 번째 호출: 401 (Bearer), 두 번째: 200 (Raw)
        let mockClient = MockAPIClient(
            responses: [
                .failure(APIError.unauthorized),
                .success(validQuotaResponseData)
            ]
        )
        let provider = ZaiUsageProvider(apiClient: mockClient)

        let usage = try await provider.fetchUsage()
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(mockClient.requestCount, 2)
    }
}

// Codex Provider: API + 로컬 병합 테스트
class CodexUsageProviderTests: XCTestCase {

    func testMergesAPIAndLocalData() async throws {
        // API: 일 단위 데이터
        let apiData = CodexAPIResponse(data: [
            CodexBucket(startTime: todayStart, endTime: todayEnd, results: [
                CodexUsageResult(inputTokens: 10000, outputTokens: 5000)
            ])
        ])
        let mockClient = MockAPIClient(response: apiData)

        // 로컬: 5시간 상세 데이터
        let localData = createMockCodexSessions(tokensInLast5Hours: 3000)

        let provider = CodexUsageProvider(
            apiClient: mockClient,
            sessionsDir: localData.directory
        )

        let usage = try await provider.fetchUsage()

        // 5시간: 로컬 데이터 (더 정확)
        XCTAssertEqual(usage.fiveHourUsage.used, 3000)
        // 주간: API 데이터
        XCTAssertEqual(usage.weeklyUsage.used, 15000)
    }
}
```

### 8.3 Integration Tests

```swift
class IntegrationTests: XCTestCase {

    /// 실제 Claude 로컬 파일이 있는 환경에서만 실행
    func testRealClaudeDataParsing() async throws {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: claudeDir.path),
            "Claude Code가 설치되지 않은 환경"
        )

        let provider = ClaudeUsageProvider()
        let isConfigured = await provider.isConfigured()
        XCTAssertTrue(isConfigured)

        let usage = try await provider.fetchUsage()
        XCTAssertTrue(usage.isAvailable)
        XCTAssertGreaterThanOrEqual(usage.fiveHourUsage.percentage, 0)
        XCTAssertLessThanOrEqual(usage.fiveHourUsage.percentage, 1.0)
    }

    /// 실제 Z.ai API 호출 (CI에서는 skip)
    func testRealZaiAPICall() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["ZAI_API_KEY"] else {
            throw XCTSkip("ZAI_API_KEY 환경변수 없음")
        }

        let provider = ZaiUsageProvider(apiKey: apiKey)
        let usage = try await provider.fetchUsage()

        XCTAssertTrue(usage.isAvailable)
        print("Z.ai 사용량: \(usage.fiveHourUsage.percentage * 100)%")
    }
}
```

### 8.4 UI 테스트

```swift
class UITests: XCTestCase {

    /// 막대 그래프가 퍼센티지에 맞게 렌더링되는지 스냅샷 테스트
    func testStackedBarRendering() {
        let data = [
            UsageData.mock(service: .claude, fiveHourPct: 0.3, weeklyPct: 0.6),
            UsageData.mock(service: .codex, fiveHourPct: 0.5, weeklyPct: 0.8),
            UsageData.mock(service: .zai, fiveHourPct: 0.1, weeklyPct: 0.4),
        ]

        let view = StackedBarView(services: data)
            .frame(width: 64, height: 20)

        // 스냅샷 비교 (SnapshotTesting 라이브러리)
        assertSnapshot(matching: view, as: .image(size: CGSize(width: 64, height: 20)))
    }

    /// 서비스 1개만 활성화된 경우 레이아웃
    func testSingleServiceLayout() {
        let data = [
            UsageData.mock(service: .zai, fiveHourPct: 0.5, weeklyPct: 0.7),
        ]

        let view = StackedBarView(services: data)
            .frame(width: 64, height: 20)

        assertSnapshot(matching: view, as: .image(size: CGSize(width: 64, height: 20)))
    }

    /// 사용량 100%일 때 표시
    func testFullUsageDisplay() {
        let data = [
            UsageData.mock(service: .claude, fiveHourPct: 1.0, weeklyPct: 1.0),
        ]

        let view = StackedBarView(services: data)
        assertSnapshot(matching: view, as: .image(size: CGSize(width: 64, height: 20)))
    }
}
```

### 8.5 Mock 객체

```swift
// Mock Usage Provider
class MockUsageProvider: UsageProviderProtocol {
    let serviceType: ServiceType
    let result: Result<UsageData, Error>
    let delay: TimeInterval
    var fetchCount = 0

    init(serviceType: ServiceType, result: Result<UsageData, Error>, delay: TimeInterval = 0) {
        self.serviceType = serviceType
        self.result = result
        self.delay = delay
    }

    func isConfigured() async -> Bool { true }

    func fetchUsage() async throws -> UsageData {
        fetchCount += 1
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        return try result.get()
    }

    func validate() async throws -> Bool { true }
}

// Mock API Client
class MockAPIClient {
    var responses: [Result<Data, Error>]
    var requestCount = 0

    func get<T: Decodable>(url: URL, headers: [String: String]) async throws -> T {
        requestCount += 1
        let response = responses[min(requestCount - 1, responses.count - 1)]
        let data = try response.get()
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// Mock UsageData Factory
extension UsageData {
    static func mock(
        service: ServiceType,
        fiveHourPct: Double = 0.5,
        weeklyPct: Double = 0.7
    ) -> UsageData {
        UsageData(
            service: service,
            fiveHourUsage: UsageMetric(
                used: fiveHourPct * 1000000,
                total: 1000000,
                unit: .tokens,
                resetTime: Date().addingTimeInterval(3600)
            ),
            weeklyUsage: UsageMetric(
                used: weeklyPct * 10000000,
                total: 10000000,
                unit: .tokens,
                resetTime: Date().addingTimeInterval(7 * 24 * 3600)
            ),
            lastUpdated: Date(),
            isAvailable: true
        )
    }
}
```

### 8.6 테스트 매트릭스

| 영역 | 테스트 항목 | 유형 | 자동화 |
|------|-----------|------|--------|
| JSONL 파서 | 정상/비정상/빈 파일/대용량 | Unit | O |
| 시간 윈도우 | 경계값, 타임존, 리셋 시각 | Unit | O |
| Claude Provider | 파일 탐색, 필터, 집계 | Unit + Integration | O |
| Codex Provider | API 응답 파싱, 로컬 병합 | Unit | O |
| Z.ai Provider | 쿼터 파싱, Auth 재시도 | Unit | O |
| ViewModel | 병렬 수집, 타이머, 에러 | Unit | O |
| Keychain | 저장/로드/삭제 | Unit | O |
| 메뉴바 그래프 | 0%/50%/100%, 1~3개 서비스 | Snapshot | O |
| 팝오버 | hover 진입/이탈, 딜레이 | UI (수동) | X |
| Login Item | 등록/해제 | Integration (수동) | X |
| 실제 API | Claude/Codex/Z.ai | Integration | 환경변수 필요 |

---

## 9. 빌드 및 배포

### 9.1 Xcode 프로젝트 설정

```
Target: AgentBar
  Bundle Identifier: com.agentbar.app
  Deployment Target: macOS 13.0
  Signing: Developer ID Application
  Hardened Runtime: YES
  Entitlements:
    - com.apple.security.network.client = YES    (API 호출)
    - com.apple.security.files.user-selected.read-only = YES (파일 읽기)

Info.plist:
  LSUIElement = YES              (Dock 숨김)
  LSMinimumSystemVersion = 13.0
```

### 9.2 배포 과정

```
1. Xcode Archive 빌드
   └─ Product > Archive

2. Export (Developer ID)
   └─ Distribute App > Developer ID

3. DMG 생성
   └─ create-dmg 또는 hdiutil

4. Notarization
   └─ xcrun notarytool submit AgentBar.dmg

5. Staple
   └─ xcrun stapler staple AgentBar.dmg

6. 배포
   └─ GitHub Releases 또는 직접 다운로드
```

---

## 10. 향후 확장 가능성

| 확장 | 설명 | 난이도 |
|------|------|--------|
| Cursor / Windsurf 추가 | 새 Provider 구현만으로 추가 가능 | 중 |
| 알림 기능 | 사용량 임계치 초과 시 macOS 알림 | 하 |
| 히스토리 그래프 | 일/주/월 사용량 추세 차트 | 중 |
| MCP 서버 연동 | Claude Code MCP 프로토콜로 직접 통신 | 상 |
| Homebrew 배포 | `brew install --cask agentbar` | 하 |

---

## 11. 보안 고려사항

| 위험 | 완화 방안 |
|------|----------|
| API 키 노출 | Keychain Services로 암호화 저장, UserDefaults 사용 금지 |
| 로컬 파일 접근 | 읽기 전용 접근, 파일 수정 절대 금지 |
| 네트워크 통신 | HTTPS만 사용, certificate pinning 고려 |
| 메모리 내 키 | 사용 후 즉시 해제, 스왑 방지를 위한 mlock 고려 |
| 사용자 데이터 | 수집/전송 없음, 모든 데이터는 로컬 처리 |

---

## 12. 용어 정의

| 용어 | 설명 |
|------|------|
| 5시간 윈도우 | 현재 시각 기준 5시간 전까지의 롤링 시간 범위. Claude Code와 Z.ai의 쿼터 리셋 주기 |
| 주간 윈도우 | 현재 시각 기준 7일 전까지의 롤링 시간 범위 |
| JSONL | JSON Lines. 줄 단위로 독립적인 JSON 객체가 기록되는 파일 형식 |
| NSStatusItem | macOS 메뉴바에 표시되는 아이콘/뷰 단위 |
| LSUIElement | Info.plist 키. true로 설정하면 앱이 Dock과 Cmd+Tab에 표시되지 않음 |
| SMAppService | macOS 13+에서 로그인 시 자동 실행을 관리하는 프레임워크 |
| Keychain | macOS의 암호화된 자격증명 저장소 |
