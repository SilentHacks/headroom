import SwiftUI

struct GeneralSettingsView: View {
    let demo: Bool
    let launchAtLogin: () -> Bool
    let toggleLaunchAtLogin: () -> Void
    @AppStorage(Pref.Key.refreshMinutes) private var refreshMinutes = 1
    @AppStorage(Pref.Key.refreshOnMenuOpen) private var refreshOnMenuOpen = true
    @AppStorage(Pref.Key.menuLayout) private var menuLayout = "all"
    @AppStorage(Pref.Key.menuBarItems) private var menuBarItems = "combined"
    @AppStorage(Pref.Key.relativeResets) private var relativeResets = true
    @AppStorage(Pref.Key.showPace) private var showPace = true
    @AppStorage(Pref.Key.hideEmptyProviders) private var hideEmptyProviders = false
    @AppStorage(Pref.Key.providerOrder) private var providerOrder = ""
    @State private var openAtLogin = false

    private var order: [Provider] { Pref.order(providerOrder) }

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Check usage every", selection: $refreshMinutes) {
                    ForEach(Pref.refreshChoices, id: \.self) { Text($0 == 1 ? "1 minute" : "\($0) minutes").tag($0) }
                }
                Toggle("Refresh when the menu opens", isOn: $refreshOnMenuOpen)
                Text("Opening the menu refreshes readings older than 30 seconds. Claude and Antigravity check every 5 minutes at most.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Menu") {
                Picker("Layout", selection: $menuLayout) {
                    Text("All providers").tag("all")
                    Text("One provider at a time").tag("paged")
                }
                Picker("Menu bar", selection: $menuBarItems) {
                    Text("One combined item").tag("combined")
                    Text("One item per provider").tag("perProvider")
                }
                Toggle("Show reset times as countdowns", isOn: $relativeResets)
                Toggle("Show pace on quota bars", isOn: $showPace)
            }
            Section("Providers") {
                List {
                    ForEach(Array(order.enumerated()), id: \.element) { index, provider in
                        HStack(spacing: 8) {
                            ProviderIcon(provider: provider).frame(width: 16, height: 16)
                            Text(provider.title)
                            Spacer()
                            Button { providerOrder = Pref.encode(Pref.moved(order, provider, by: -1)) } label: {
                                Image(systemName: "chevron.up")
                            }.disabled(index == 0).accessibilityLabel("Move \(provider.title) up")
                            Button { providerOrder = Pref.encode(Pref.moved(order, provider, by: 1)) } label: {
                                Image(systemName: "chevron.down")
                            }.disabled(index == order.count - 1).accessibilityLabel("Move \(provider.title) down")
                        }.buttonStyle(.borderless)
                    }.onMove { source, destination in
                        var updated = order
                        updated.move(fromOffsets: source, toOffset: destination)
                        providerOrder = Pref.encode(updated)
                    }
                }.frame(height: 220)
                HStack {
                    Text("Drag to reorder.").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore default") { providerOrder = "" }.disabled(providerOrder.isEmpty)
                }
                Toggle("Hide providers without accounts in the sidebar", isOn: $hideEmptyProviders)
            }
            Section("General") {
                Toggle("Open at Login", isOn: Binding(get: { openAtLogin }, set: { _ in
                    toggleLaunchAtLogin()
                    Task { try? await Task.sleep(for: .milliseconds(600)); openAtLogin = launchAtLogin() }
                })).disabled(demo)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .onAppear { openAtLogin = launchAtLogin() }
    }
}
