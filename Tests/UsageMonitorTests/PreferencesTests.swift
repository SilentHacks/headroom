import Foundation
import Testing
@testable import UsageMonitor

@Test func providerOrderKeepsSavedProvidersThenDefaultsAndDropsUnknownOrRepeated() {
    #expect(Array(Pref.order("").prefix(4)) == [.claude, .codex, .devin, .antigravity])
    let order = Pref.order("amp,unknown,claude,amp")
    #expect(Array(order.prefix(3)) == [.amp, .claude, .codex])
    #expect(order.count == Provider.allCases.count)
    #expect(Set(order) == Set(Provider.allCases))
    #expect(Pref.order(Pref.encode(order)) == order)
    #expect(Pref.moved(order, .amp, by: -1) == order)
    #expect(Array(Pref.moved(order, .amp, by: 1).prefix(2)) == [.claude, .amp])
}

@Test func entriesFollowProviderOrderAndKeepAccountOrderWithinAProvider() {
    let first = AccountEntry(account: Account(label: "a", provider: .codex))
    let second = AccountEntry(account: Account(label: "b", provider: .claude))
    let third = AccountEntry(account: Account(label: "c", provider: .codex))
    let sorted = Pref.sorted([first, second, third], order: Pref.order("codex,claude"))
    #expect(sorted.map(\.account.label) == ["a", "c", "b"])
}

@Test func refreshMinimumsKeepSlowProvidersAtFiveMinutes() {
    #expect(Pref.effectiveMinutes(.codex, minutes: 1) == 1)
    #expect(Pref.effectiveMinutes(.claude, minutes: 1) == 5)
    #expect(Pref.effectiveMinutes(.antigravity, minutes: 10) == 10)
}

@Test func countdownsUseTheTwoLargestUnits() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    #expect(now.addingTimeInterval(3 * 86400 + 20 * 3600 + 59).countdownText(from: now) == "3d 20h")
    #expect(now.addingTimeInterval(4 * 3600 + 12 * 60).countdownText(from: now) == "4h 12m")
    #expect(now.addingTimeInterval(20).countdownText(from: now) == "1m")
    #expect(now.addingTimeInterval(-60).countdownText(from: now) == "1m")
}

@Test func paceComparesQuotaLeftWithAnEvenBurn() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let weekly = UsageMetric(title: "Weekly", kind: .quota, value: 76, resetsAt: now.addingTimeInterval(3.5 * 86400))
    let pace = try #require(QuotaPace(weekly, now: now))
    #expect(abs(pace.expectedRemaining - 50) < 0.001)
    #expect(abs(pace.reserve - 26) < 0.001)
    #expect(abs((pace.headroom ?? 0) - 1.52) < 0.001)
    #expect(pace.runsOutAt == nil)
    #expect(pace.ticks.count == 6)
    #expect(pace.summary(now: now) == "26% in reserve · Lasts until reset · 1.5× headroom")

    let session = UsageMetric(title: "5-hour", kind: .quota, value: 20, resetsAt: now.addingTimeInterval(2.5 * 3600))
    let fast = try #require(QuotaPace(session, now: now))
    #expect(abs(fast.reserve + 30) < 0.001)
    #expect(fast.runsOutAt == now.addingTimeInterval(37.5 * 60))
    #expect(fast.ticks.isEmpty)
    #expect(fast.summary(now: now) == "30% over pace · Runs out in 37m · 0.4× headroom")
}

@Test func paceStaysUnavailableWithoutAKnownWindowOrPlausibleReset() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    #expect(QuotaPace(.init(title: "Agent", kind: .quota, value: 50, resetsAt: now.addingTimeInterval(3600)), now: now) == nil)
    #expect(QuotaPace(.init(title: "Weekly", kind: .quota, value: 50, resetsAt: now.addingTimeInterval(8 * 86400)), now: now) == nil)
    #expect(QuotaPace(.init(title: "Weekly", kind: .quota, value: 50), now: now) == nil)
    #expect(QuotaPace(.init(title: "Weekly", kind: .quota, value: nil, resetsAt: now.addingTimeInterval(86400)), now: now) == nil)
    #expect(QuotaPace(.init(title: "Daily", kind: .balance, value: 5, unit: "USD", resetsAt: now.addingTimeInterval(3600)), now: now) == nil)
    #expect(UsageMetric(title: "Opus · Weekly", kind: .quota, value: 1).windowLength == TimeInterval(7 * 86400))
    #expect(UsageMetric(title: "8-hour", kind: .quota, value: 1).windowLength == TimeInterval(8 * 3600))
}
