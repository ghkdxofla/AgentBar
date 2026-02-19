# Usage History 구현 계획 (7d Consistency 포함)

## 1. 목적

Settings의 `History` 탭에서 다음을 동시에 제공한다.

1. 일별 사용 강도 가시화 (`Daily Heatmap`)
2. 7d 윈도우를 사이클 단위로 얼마나 꾸준히 끝까지 쓰는지 (`7d Cycle Consistency`)

핵심 판단 질문:
- 최근 기간 동안 매일 얼마나 사용했는가
- 7d 리밋을 사이클마다 얼마나 안정적으로 소진했는가

## 2. 범위

포함:
- 일 단위 히트맵 (기존 방향 유지)
- 7d 사이클 스트립/지표 (신규 핵심)
- 히스토리 저장소(일 집계 + secondary 샘플)
- 서비스/윈도우/기간 선택 UI
- 단위 테스트 + 기존 테스트 보강

제외:
- 과거 로그 백필
- CSV export
- 메뉴바(popover/status bar) 히스토리 표시

## 3. 윈도우 규칙

History는 `UsageData`의 공통 구조를 기준으로 동작한다.

- `primary`: `UsageData.fiveHourUsage`
- `secondary`: `UsageData.weeklyUsage` (없으면 미지원)

7d Consistency 패널은 아래 조건에서만 활성화한다.

- 선택 윈도우가 `secondary`
- 선택 서비스의 `weeklyLabel == "7d"`

즉, Claude/Codex에서만 7d 사이클 패널을 노출한다.

## 4. 데이터 모델

신규 파일: `AgentBar/Models/UsageHistory.swift`

```swift
import Foundation

struct UsageHistoryDayRecord: Codable, Sendable, Equatable {
    let service: ServiceType
    let dayStart: Date
    var primaryPeakRatio: Double
    var primaryAverageRatio: Double
    var secondaryPeakRatio: Double?
    var secondaryAverageRatio: Double?
    var sampleCount: Int
    var lastSampleAt: Date
}

// 7d 사이클 분석용 secondary 시계열 샘플
struct UsageHistorySecondarySample: Codable, Sendable, Equatable {
    let service: ServiceType
    let sampledAt: Date
    let ratio: Double        // 0...1
    let resetAt: Date        // secondary resetTime
}

struct UsageHistoryStoreFile: Codable, Sendable {
    var schemaVersion: Int
    var dayRecords: [UsageHistoryDayRecord]
    var secondarySamples: [UsageHistorySecondarySample]
}

enum UsageHistoryWindow: String, CaseIterable, Sendable {
    case primary
    case secondary
}
```

정규화 규칙:
- ratio는 항상 `0...1` clamp
- `resetAt`은 초 단위 오차 제거를 위해 minute 단위로 truncate 후 저장

## 5. 저장소 설계

신규 파일: `AgentBar/Infrastructure/UsageHistoryStore.swift`

타입:
- `protocol UsageHistoryStoreProtocol: Sendable`
- `actor UsageHistoryStore: UsageHistoryStoreProtocol`

필수 API:

```swift
protocol UsageHistoryStoreProtocol: Sendable {
    func record(samples: [UsageData], recordedAt: Date) async
    func dayRecords(for service: ServiceType, since: Date, until: Date) async -> [UsageHistoryDayRecord]
    func secondarySamples(for service: ServiceType, since: Date, until: Date) async -> [UsageHistorySecondarySample]
    func availableServices(since: Date, until: Date) async -> [ServiceType]
}
```

저장 경로:
- `~/Library/Application Support/AgentBar/usage-history.json`

내부 정책:
- `schemaVersion = 2`
- `dayRecords` retention: 365일
- `secondarySamples` retention: 120일
- 저장은 `.atomic` write
- decode 실패 시 기존 파일을 `usage-history.corrupt-<unix>.json`으로 이동 후 빈 스토어로 초기화

샘플 기록 정책 (`record(samples:recordedAt:)`):
1. 일 집계(`UsageHistoryDayRecord`) 갱신
2. `weeklyUsage?.resetTime`이 있는 샘플만 `UsageHistorySecondarySample` 저장
3. secondary 샘플은 5분 버킷 upsert로 저장 크기 제한
   - 버킷 키: `(service, floor(sampledAt to 5min), resetAt)`
   - 동일 버킷 충돌 시 `ratio`가 큰 샘플 유지
4. retention prune 후 파일 저장

## 6. 수집 파이프라인 변경

수정 파일: `AgentBar/ViewModels/UsageViewModel.swift`

변경 사항:
1. initializer에 `historyStore: UsageHistoryStoreProtocol` 주입
2. provider fetch 결과를 `success`와 `failure`로 분리 추적
3. `success`만 history에 기록
4. `failure`는 기존 동작대로 synthetic zero row 표시하되 history 기록 금지
5. 기록 완료 후 `Notification.Name.usageHistoryChanged` 발행

신규 알림:
- `AgentBar/Views/Settings/SettingsView.swift`의 `Notification.Name` extension에 추가
- `static let usageHistoryChanged = Notification.Name("AgentBarUsageHistoryChanged")`

## 7. ViewModel 설계

신규 파일: `AgentBar/ViewModels/UsageHistoryViewModel.swift`

### 7.1 상태

- `@Published var selectedService: ServiceType?`
- `@Published var selectedWindow: UsageHistoryWindow = .primary`
- `@Published var selectedRangeWeeks: Int = 8` (`4`, `8`, `12`)
- `@Published var heatmapCells: [UsageHistoryHeatmapCell]`
- `@Published var dailySummary: UsageHistorySummary`
- `@Published var cycleSummary: UsageHistoryCycleSummary`
- `@Published var cycleCells: [UsageHistoryCycleCell]`
- `@Published var isSevenDayCycleAvailable: Bool`

### 7.2 보조 모델

```swift
struct UsageHistoryHeatmapCell: Identifiable, Sendable {
    let id: String
    let date: Date
    let ratio: Double
    let level: Int      // 0...4
    let sampleCount: Int
    let peakRatio: Double
    let averageRatio: Double
}

struct UsageHistorySummary: Sendable, Equatable {
    let limitHitDays: Int
    let nearLimitDays: Int
    let averageDailyPeakRatio: Double
    let lastHitDate: Date?
}

struct UsageHistoryCycleCell: Identifiable, Sendable {
    let id: String
    let cycleStart: Date
    let cycleEnd: Date
    let peakRatio: Double
    let level: Int      // 0...4
    let reached80: Bool
    let reached100: Bool
    let daysTo80: Int?
    let daysTo100: Int?
    let highBandHours: Double
}

struct UsageHistoryCycleSummary: Sendable, Equatable {
    let completedCycles: Int
    let totalClosedCycles: Int
    let completionRate: Double       // 0...1
    let averageDaysTo80: Double?
    let averageDaysTo100: Double?
    let averageHighBandHours: Double
    let currentCompletionStreak: Int
}
```

### 7.3 일별 히트맵 계산

- 7행(일~토), N열(선택 주수)
- 현재 날짜 포함 최근 N주 고정 길이
- 데이터 없는 날짜는 ratio=0
- 레벨 매핑:
  - `0`: `ratio == 0`
  - `1`: `0 < ratio <= 0.25`
  - `2`: `0.25 < ratio <= 0.5`
  - `3`: `0.5 < ratio <= 0.75`
  - `4`: `0.75 < ratio <= 1.0`

### 7.4 7d 사이클 계산

입력:
- `secondarySamples` (service panel 단위)

사이클 그룹 키:
- `resetAt` (minute-truncated 값)

사이클 정의:
- 같은 `resetAt`을 가진 샘플 집합 = 하나의 사이클
- `cycleEnd = resetAt`
- `cycleStart = 이전 cycleEnd` (첫 사이클은 `min(sampledAt)` 사용)
- `closed cycle`: `cycleEnd <= now`

사이클 지표:
- `peakRatio = max(ratio)`
- `reached80 = peakRatio >= 0.8`
- `reached100 = peakRatio >= 1.0`
- `daysTo80`: `ratio >= 0.8` 첫 샘플의 (cycleStart 기준 day offset)
- `daysTo100`: `ratio >= 1.0` 첫 샘플의 (cycleStart 기준 day offset)
- `highBandHours`:
  - 샘플 정렬 후 인접 샘플 간 구간 합
  - 이전 샘플 ratio가 `>=0.8`인 구간만 가산
  - 과대추정 방지를 위해 한 구간 최대 30분 cap

사이클 요약:
- `completedCycles`: closed cycle 중 `reached100` 개수
- `completionRate = completedCycles / totalClosedCycles`
- `averageDaysTo80`, `averageDaysTo100`: 값 존재하는 cycle 평균
- `averageHighBandHours`: closed cycle 평균
- `currentCompletionStreak`: 최신 closed cycle부터 연속 `reached100` 개수

표시 개수:
- 최근 12개 closed cycle을 `cycleCells`로 노출

## 8. UI 설계

신규 파일: `AgentBar/Views/Settings/UsageHistoryTabView.swift`

구성:
1. 상단 컨트롤
- 윈도우 Picker (`primary`/`secondary`)
- 기간 Picker (`4w`/`8w`/`12w`)
- 짧은 가이드 텍스트:
  - Daily Heatmap: `1 tile = 1 day`
  - 7d Cycle Consistency: `1 tile = 1 reset cycle`

2. 서비스 패널 목록
- 선택 가능한 모든 서비스를 한 화면에 동시 표시
- 정렬 기준:
  - 1순위: 사용 빈도(활성 일수) 내림차순
  - 2순위: 평균 일별 피크 내림차순
  - 3순위: 기존 서비스 우선순위

3. Daily Heatmap 섹션 (서비스별)
- contribution 스타일 타일
- 요약 4개:
  - `Limit Hit Days`
  - `Near Limit Days`
  - `Avg Daily Peak`
  - `Last Hit Date`

4. 7d Cycle Consistency 섹션 (서비스별 조건부 표시)
- 조건: `isSevenDayCycleAvailable == true`
- `UsageHistoryCycleStripView` (신규 내부 컴포넌트)
  - 최근 12사이클 타일/스트립
  - 색상은 `peakRatio` 레벨
- 요약 5개:
  - `Cycle Completion Rate`
  - `Completed Cycles` (`X / Y`)
  - `Avg Days to 80%`
  - `Avg Days to 100%`
  - `Current Completion Streak`
- 보조 지표:
  - `Avg High-Band Hours (>=80%)`

5. 빈 상태
- 데이터 없음: `"No history yet. Keep AgentBar running to collect usage."`
- 사이클 없음: `"Not enough 7d cycle data yet."`

색상:
- level 0: `Color.gray.opacity(0.15)`
- level 1~4: `service.darkColor.opacity(0.25/0.45/0.7/1.0)`

툴팁:
- 일별 타일: 날짜, peak %, average %, sample count
- 사이클 타일: cycle range, peak %, reached80/100, daysTo80/100, highBandHours

## 9. Settings 통합

수정 파일: `AgentBar/Views/Settings/SettingsView.swift`

- `SettingsTab`에 `.history` 추가
- `TabView`에 `History` 탭 추가 (가장 오른쪽)
- `historyTab`에서 `UsageHistoryTabView` 렌더링

## 10. 변경 파일 목록

신규:
- `AgentBar/Models/UsageHistory.swift`
- `AgentBar/Infrastructure/UsageHistoryStore.swift`
- `AgentBar/ViewModels/UsageHistoryViewModel.swift`
- `AgentBar/Views/Settings/UsageHistoryTabView.swift`
- `AgentBarTests/UsageHistoryStoreTests.swift`
- `AgentBarTests/UsageHistoryViewModelTests.swift`

수정:
- `AgentBar/ViewModels/UsageViewModel.swift`
- `AgentBar/Views/Settings/SettingsView.swift`
- `AgentBarTests/UsageViewModelTests.swift`
- `AgentBarTests/SettingsViewBehaviorTests.swift`

## 11. 테스트 계획

### 11.1 UsageHistoryStoreTests

필수:
1. day record peak/avg/sampleCount 갱신
2. secondary sample 5분 버킷 upsert
3. retention prune (day 365일, sample 120일)
4. 저장/재로딩 round-trip
5. 손상 파일 복구(corrupt rename 후 초기화)

### 11.2 UsageHistoryViewModelTests

필수:
1. heatmap 셀 수(`7 * weeks`) 및 레벨 매핑 경계값
2. daily summary 계산 정확성
3. cycle grouping(`resetAt` 기준) 정확성
4. cycle summary 계산 정확성
   - completion rate
   - daysTo80/100
   - streak
   - highBandHours(cap 반영)
5. secondary 미지원 또는 non-7d 서비스에서 cycle 패널 비활성

### 11.3 기존 테스트 보강

- `UsageViewModelTests`
  - 성공 fetch만 history 기록
  - 실패 synthetic zero는 history 미기록

- `SettingsViewBehaviorTests`
  - History 탭 포함 시 body 빌드 안정성

## 12. 구현 순서

1. `UsageHistory.swift` 추가 (schema v2)
2. `UsageHistoryStore.swift` 구현 + store 테스트
3. `UsageViewModel` history 주입/record 연결 + 테스트 보강
4. `UsageHistoryViewModel.swift` 구현 (daily + cycle) + 테스트
5. `UsageHistoryTabView.swift` 구현 (heatmap + cycle strip)
6. `SettingsView.swift` 탭 통합
7. 전체 테스트 실행 후 보정

## 13. 완료 기준

- Settings `History` 탭에서 일별 타일 히트맵이 정상 표시된다.
- Claude/Codex `secondary(7d)` 선택 시 `7d Cycle Consistency` 섹션이 표시된다.
- 사이클 completion rate/streak/days-to-threshold/high-band 지표가 계산된다.
- synthetic zero fallback은 히스토리에 기록되지 않는다.
- 신규/기존 테스트가 모두 통과한다.

## 14. v0.5 이후 리팩토링 메모 (2026-02-20)

### 14.1 저장소 write 경량화
- `UsageHistoryStore`는 snapshot(`usage-history.json`) + append log(`usage-history.events.jsonl`) 구조로 동작한다.
- 신규 샘플 기록 시:
  1. 메모리 state 반영
  2. 이벤트를 append log에 추가
  3. log가 임계치(이벤트 수/파일 크기) 도달 시 compact(정렬 + snapshot 저장 + log 제거)
- 효과:
  - 매 샘플마다 전체 JSON 파일 rewrite를 피함
  - crash 이후에도 log replay로 복구 가능

### 14.2 secondary 평균 분모 분리
- `UsageHistoryDayRecord.secondarySampleCount` 추가.
- secondary 평균(`secondaryAverageRatio`, `secondaryAverageUsed`)은 전체 `sampleCount`가 아니라 `secondarySampleCount` 기준으로 계산.
- secondary가 없는 샘플이 섞여도 평균이 희석되지 않는다.

### 14.3 History refresh 경쟁 상태 방지
- `UsageHistoryViewModel`에 `refreshGeneration` + `refreshTask` 도입.
- 새 refresh 요청이 오면 이전 task를 취소하고 generation mismatch 결과를 폐기한다.
- 늦게 끝난 이전 refresh가 최신 UI 상태를 덮어쓰는 문제를 방지한다.

### 14.4 Keychain load cache 안정화
- `KeychainManager.load`는 load 결과를 `LoadOutcome(value, shouldCache)`로 처리한다.
- `errSecInteractionNotAllowed` 등 transient 실패는 캐시하지 않는다.
- `errSecItemNotFound` 등 안정 상태만 캐시하여, 일시 실패 후 복구 시 재시도가 가능하다.
