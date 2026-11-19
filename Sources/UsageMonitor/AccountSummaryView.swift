import AppKit
import SwiftUI

// Transparent content shared by the native menu and the account management window.
struct AccountSummaryView: View {
    let entry: AccountEntry
    var compact = false
    @AppStorage(Pref.Key.relativeResets) private var relativeResets = true
    @AppStorage(Pref.Key.showPace) private var showPace = true

    private var textFont: Font { .body }

    var body: some View {
        TimelineView(.periodic(from: .now, by: entry.snapshot?.availabilityChangeDates.isEmpty == false ? 1 : 60)) { context in
            summary(at: context.date)
        }
    }

    private func summary(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName).font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    HStack {
                        if let plan = entry.snapshot?.plan {
                            Text(plan).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if entry.refreshing { ProgressView().controlSize(.mini) }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 9) {
                    Text(entry.displayName).font(.headline).lineLimit(1).truncationMode(.middle)
                        .help(entry.displayName)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        if let plan = entry.snapshot?.plan {
                            Text(plan).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(1).help(plan)
                        }
                        if entry.refreshing { ProgressView().controlSize(.small) }
                    }
                }
            }
            if let snapshot = entry.snapshot {
                // The menu shows freshness only once a reading is stale.
                if !compact || now.timeIntervalSince(snapshot.fetchedAt) > 600 {
                    Text("Updated \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .help("Last successful read: \(snapshot.fetchedAt.formatted())")
                }
                let metrics = snapshot.metrics(at: now)
                let creditLeft = metrics.first { $0.title == "Credits left" }
                let creditCap = metrics.first { $0.title == "Credit limit" }
                let creditQuota = metrics.first { $0.title == "Individual credit quota" }
                let displayedMetrics = metrics.filter {
                    !["Credits left", "Credits used", "Credit limit", "Individual credit quota"].contains($0.title)
                        || creditLeft == nil || creditCap == nil
                }
                let rows = ForEach(Array(displayedMetrics.filter { $0.kind != .note }.enumerated()), id: \.offset) { _, metric in
                    metricRow(metric)
                }
                if compact {
                    rows
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .topLeading)],
                              alignment: .leading, spacing: 18) {
                        rows
                    }
                }
                ForEach(Array(displayedMetrics.filter { $0.kind == .note }.enumerated()), id: \.offset) { _, metric in
                    Text("\(metric.title): \(metric.detail ?? "Unavailable")")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.account.provider == .codex {
                    Divider()
                    resetCreditsRow(snapshot, now: now)
                }
                if let left = creditLeft, let cap = creditCap {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Credits").font(textFont.weight(.medium))
                            Spacer()
                            Text("\(formatted(left)) left").font(textFont.monospacedDigit())
                        }
                        if let quota = creditQuota { quotaBar(quota) }
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(formatted(cap)) credit limit").font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            if let reset = creditQuota?.resetsAt { resetLabel(reset).fixedSize() }
                        }
                    }.help("Remaining individual allowance, not the wallet balance")
                }
            } else if let message = entry.error {
                UsageWarning(message: message)
            } else {
                Text(!entry.account.provider.supportsRead ? "Usage unavailable."
                     : entry.refreshing ? "Checking usage…" : "Connect to see usage.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func metricRow(_ metric: UsageMetric) -> some View {
        if !compact, metric.kind == .spend,
           [.anthropicAPI, .openAIAPI].contains(entry.account.provider) {
            VStack(alignment: .leading, spacing: 6) {
                Text(metric.title).font(.callout).foregroundStyle(.secondary)
                Text(formatted(metric)).font(.system(size: 28, weight: .semibold).monospacedDigit())
                if let detail = metric.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if metric.kind == .quota {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(metric.title).font(textFont.weight(.medium))
                        quotaValue(metric)
                        Spacer(minLength: 12)
                        quotaReset(metric)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(metric.title).font(textFont.weight(.medium))
                            quotaValue(metric)
                        }.fixedSize()
                        quotaReset(metric)
                    }
                }
                let pace = showPace ? QuotaPace(metric, now: Date()) : nil
                quotaBar(metric, pace: pace)
                if let pace {
                    Text(pace.summary(now: Date())).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title == "Credit balance" ? "Wallet credits" : metric.title).font(textFont)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if metric.kind != .note {
                        Text(formatted(metric)).font(textFont.monospacedDigit()).fixedSize()
                    }
                }
                if let reset = metric.resetsAt { resetLabel(reset) }
                if let detail = metric.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : nil).fixedSize(horizontal: false, vertical: true).help(detail)
                }
            }
        }
    }

    private func quotaValue(_ metric: UsageMetric) -> some View {
        Text(metric.value == nil ? "Unavailable" : "\(MenuBarAccountImage.text(metric)) left")
            .font(textFont.monospacedDigit()).foregroundStyle(metric.remainingColor)
    }

    @ViewBuilder private func quotaBar(_ metric: UsageMetric, pace: QuotaPace? = nil) -> some View {
        if let remaining = metric.value, remaining.isFinite, (0...100).contains(remaining) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.1)).frame(height: 6)
                    Capsule().fill(metric.remainingColor).frame(width: width * remaining / 100, height: 6)
                    if let pace {
                        ForEach(pace.ticks, id: \.self) { tick in
                            Rectangle().fill(.primary.opacity(0.3)).frame(width: 1, height: 6).offset(x: width * tick - 0.5)
                        }
                        // Where an even burn would leave the quota now.
                        Capsule().fill(pace.reserve >= 0 ? Color.green : Color.orange).frame(width: 2, height: 10)
                            .offset(x: min(max(width * pace.expectedRemaining / 100 - 1, 0), max(width - 2, 0)))
                    }
                }.frame(maxHeight: .infinity)
            }.frame(height: pace == nil ? 6 : 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.title) remaining")
                .accessibilityValue(MenuBarAccountImage.text(metric) + (pace.map { ", " + $0.summary(now: Date()) } ?? ""))
        }
    }

    private func resetCreditsRow(_ snapshot: UsageSnapshot, now: Date) -> some View {
        let expiries = snapshot.unusedResetExpirations(at: now).map(\.date).sorted()
        let soon = expiries.first.map { $0.timeIntervalSince(now) < 86400 } ?? false
        let countdowns = expiries.prefix(4).map { $0.countdownText(from: now) }.joined(separator: " · ")
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Limit reset credits").font(textFont.weight(.medium))
                Text(snapshot.resetCredits.map { "\($0.availableCount) available" } ?? "Unavailable")
                    .font(textFont.monospacedDigit())
                Spacer(minLength: 12)
                if !expiries.isEmpty { resetExpiries(countdowns, expiries: expiries, soon: soon) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Limit reset credits").font(textFont.weight(.medium))
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.resetCredits.map { "\($0.availableCount) available" } ?? "Unavailable")
                        .font(textFont.monospacedDigit())
                    Spacer(minLength: 12)
                    if !expiries.isEmpty { resetExpiries(countdowns, expiries: expiries, soon: soon) }
                }
            }
        }
    }

    private func resetExpiries(_ countdowns: String, expiries: [Date], soon: Bool) -> some View {
        Label(countdowns, systemImage: "clock")
            .font(.subheadline.monospacedDigit()).foregroundStyle(soon ? Color.orange : Color.secondary)
            .help("Expire " + expiries.map { $0.usageResetText() }.joined(separator: ", "))
            .accessibilityLabel("Expire in " + countdowns)
            .fixedSize()
    }

    @ViewBuilder private func quotaReset(_ metric: UsageMetric) -> some View {
        if let reset = metric.resetsAt { resetLabel(reset).fixedSize() }
        else { Text("Reset unavailable").font(.subheadline).foregroundStyle(.secondary).fixedSize() }
    }

    private func resetLabel(_ reset: Date) -> some View {
        let now = Date()
        let date = relativeResets ? "in \(reset.countdownText(from: now))"
            : compact ? reset.formatted(.dateTime.month(.abbreviated).day().hour().minute()) : reset.usageResetText()
        return Text(reset <= now ? "Reset passed — refresh" : "Resets \(date)")
            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .help(reset.usageResetText())
    }

    private func formatted(_ metric: UsageMetric) -> String {
        guard let value = metric.value, value.isFinite else { return "Unavailable" }
        if ["USD", "EUR", "GBP", "CAD", "CNY"].contains(metric.unit) {
            return value.formatted(.currency(code: metric.unit))
        }
        return value.formatted(.number.precision(.fractionLength(0...2))) + (metric.unit == "credits" ? "" : " \(metric.unit)")
    }
}

struct ProviderAccountGrid<Content: View>: View {
    let entries: [AccountEntry]
    var actions: NSMenu? = nil
    var open: (() -> Void)? = nil
    @ViewBuilder var content: (AccountEntry) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let provider = entries.first?.account.provider {
                HStack(spacing: 8) {
                    if let open {
                        Button(action: open) {
                            HStack(spacing: 8) {
                                ProviderIcon(provider: provider).frame(width: 22, height: 22)
                                Text(provider.title).font(.headline)
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Open \(provider.title) in Headroom")
                            .accessibilityIdentifier("openProvider-\(provider.rawValue)")
                    } else {
                        ProviderIcon(provider: provider).frame(width: 22, height: 22)
                        Text(provider.title).font(.headline)
                    }
                    Spacer(minLength: 0)
                    if let actions {
                        MenuActionsButton(menu: actions).frame(width: 24, height: 24)
                    }
                }
            }
            ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: 12) {
                    content(entries[start]).frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    if start + 1 < entries.count {
                        content(entries[start + 1]).frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    } else if entries.count != 1 {
                        Color.clear.frame(minWidth: 0, maxWidth: .infinity, maxHeight: 1)
                    }
                }
                if start + 2 < entries.count { Divider() }
            }
        }
    }
}

private struct MenuActionsButton: NSViewRepresentable {
    let menu: NSMenu

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageOnly
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.setAccessibilityLabel("Headroom actions")
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        menu.items.first?.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Headroom actions")
        button.menu = menu
    }
}

struct UsageWarning: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }.font(.callout).accessibilityElement(children: .combine)
    }
}

struct ProviderIcon: View {
    let provider: Provider
    var body: some View {
        if let image = provider.logo {
            if image.isTemplate {
                Rectangle().fill(.foreground)
                    .mask { Image(nsImage: image).resizable().scaledToFit() }
                    .accessibilityLabel(provider.title)
            } else {
                Image(nsImage: image).resizable().scaledToFit().accessibilityLabel(provider.title)
            }
        } else {
            Text(String(provider.title.prefix(1))).font(.headline).accessibilityLabel(provider.title)
        }
    }
}

extension Provider {
    var logo: NSImage? {
        let name: String
        switch self {
        case .claude: name = "claude-logo"
        case .codex: name = "codex-logo"
        case .openAIAPI: name = "openai-logo"
        case .amp: name = "amp-logo"
        case .openRouter: name = "openrouter-logo"
        case .anthropicAPI: name = "anthropic-logo"
        case .xaiAPI: name = "xai-logo"
        case .grok: name = "grok-logo"
        case .cursor: name = "grok-bot-logo"
        case .zai: name = "zai-logo"
        case .searchAPI: name = "searchapi-logo"
        case .dataForSEO: name = "dataforseo-logo"
        case .firecrawl: name = "firecrawl-logo"
        case .serpAPI: name = "serpapi-logo"
        case .tavily: name = "tavily-logo"
        case .jina: name = "jina-logo"
        case .exa: name = "exa-logo"
        case .parallel: name = "parallel-logo"
        case .valyu: name = "valyu-logo"
        case .you: name = "you-logo"
        case .brave: name = "brave-logo"
        case .perplexity: name = "perplexity-logo"
        case .gemini: name = "gemini-logo"
        case .kagi: name = "kagi-logo"
        case .devin: name = "devin-logo"
        case .antigravity: name = "antigravity-logo"
        }
        let image = Bundle.module.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = [Self.codex, .openAIAPI, .anthropicAPI, .xaiAPI, .grok, .amp, .valyu, .devin].contains(self)
        return image
    }
}

// Provider tabs for the one-provider-at-a-time menu.
struct ProviderPicker: View {
    let providers: [Provider]
    let selected: Provider
    let select: (Provider) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(providers) { provider in
                Button { select(provider) } label: {
                    ProviderIcon(provider: provider).frame(width: 18, height: 18).padding(6)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(provider == selected ? Color.accentColor.opacity(0.25) : Color.clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(provider.title)
                    .accessibilityLabel(provider.title)
                    .accessibilityAddTraits(provider == selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}
