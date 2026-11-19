import Foundation

// App-wide settings, stored in UserDefaults. Views bind to the same keys with @AppStorage.
enum Pref {
    enum Key {
        static let refreshMinutes = "refreshMinutes", refreshOnMenuOpen = "refreshOnMenuOpen"
        static let menuLayout = "menuLayout", menuBarItems = "menuBarItems", pagedProvider = "pagedProvider"
        static let relativeResets = "relativeResets", showPace = "showPace"
        static let hideEmptyProviders = "hideEmptyProviders", providerOrder = "providerOrder"
    }

    static let refreshChoices = [1, 2, 5, 10, 15]
    private static var defaults: UserDefaults { .standard }

    static var refreshMinutes: Int {
        let minutes = defaults.integer(forKey: Key.refreshMinutes)
        return refreshChoices.contains(minutes) ? minutes : 1
    }
    static var refreshOnMenuOpen: Bool { defaults.object(forKey: Key.refreshOnMenuOpen) as? Bool ?? true }
    static var pagedMenu: Bool { defaults.string(forKey: Key.menuLayout) == "paged" }
    static var perProviderMenuBar: Bool { defaults.string(forKey: Key.menuBarItems) == "perProvider" }
    static var providerOrder: [Provider] { order(defaults.string(forKey: Key.providerOrder) ?? "") }

    // Claude and Antigravity start a helper or share a strict limit, so they never poll faster.
    static func minimumMinutes(_ provider: Provider) -> Int { [.claude, .antigravity].contains(provider) ? 5 : 1 }
    static func effectiveMinutes(_ provider: Provider, minutes: Int) -> Int { max(minutes, minimumMinutes(provider)) }

    // Saved providers first, then any not yet ordered in their default position.
    static func order(_ raw: String) -> [Provider] {
        var seen = Set<Provider>()
        let saved = raw.split(separator: ",").compactMap { Provider(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        return saved + Provider.allCases.filter { !seen.contains($0) }
    }

    static func encode(_ order: [Provider]) -> String { order.map(\.rawValue).joined(separator: ",") }

    static func moved(_ order: [Provider], _ provider: Provider, by offset: Int) -> [Provider] {
        var updated = order
        guard let index = updated.firstIndex(of: provider), updated.indices.contains(index + offset) else { return order }
        updated.swapAt(index, index + offset)
        return updated
    }

    static func sorted(_ entries: [AccountEntry], order: [Provider] = providerOrder) -> [AccountEntry] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return entries.enumerated().sorted {
            (rank[$0.element.account.provider] ?? 0, $0.offset) < (rank[$1.element.account.provider] ?? 0, $1.offset)
        }.map(\.element)
    }
}

extension Date {
    // "3d 20h", "4h 12m" or "9m" until this date.
    func countdownText(from now: Date) -> String {
        let seconds = max(0, Int(timeIntervalSince(now)))
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }
}

extension UsageMetric {
    // Only windows whose length is implied by their name; others show no pace.
    var windowLength: TimeInterval? {
        let name = title.lowercased()
        if name.hasPrefix("weekly") || name.hasSuffix("· weekly") { return 7 * 86400 }
        if name.hasPrefix("daily") || name.hasSuffix("· daily") { return 86400 }
        if let match = name.firstMatch(of: /(?:^|· )(\d{1,3})-hour/), let hours = Int(match.1), hours > 0 {
            return TimeInterval(hours) * 3600
        }
        return nil
    }
}

// Compares quota left with an even burn across the window.
struct QuotaPace: Equatable {
    let expectedRemaining: Double
    let reserve: Double
    let headroom: Double?
    let runsOutAt: Date?
    let ticks: [Double]

    init?(_ metric: UsageMetric, now: Date) {
        guard metric.kind == .quota, metric.unit == "%", let remaining = metric.value, remaining.isFinite,
              (0...100).contains(remaining), let reset = metric.resetsAt, let length = metric.windowLength, reset > now
        else { return nil }
        let left = reset.timeIntervalSince(now)
        let elapsed = length - left
        guard left <= length, elapsed >= length * 0.01 else { return nil }
        expectedRemaining = 100 * left / length
        reserve = remaining - expectedRemaining
        headroom = expectedRemaining >= 1 ? remaining / expectedRemaining : nil
        let rate = (100 - remaining) / elapsed
        runsOutAt = rate > 0 && remaining / rate < left ? now.addingTimeInterval(remaining / rate) : nil
        ticks = length >= 7 * 86400 ? (1..<7).map { Double($0) / 7 } : []
    }

    func summary(now: Date) -> String {
        let points = Int(abs(reserve).rounded())
        let pace = reserve >= 0 ? "\(points)% in reserve" : "\(points)% over pace"
        let lasting = runsOutAt.map { "Runs out in \($0.countdownText(from: now))" } ?? "Lasts until reset"
        let room = headroom.map { " · " + $0.formatted(.number.precision(.fractionLength(1))) + "× headroom" } ?? ""
        return "\(pace) · \(lasting)\(room)"
    }
}
