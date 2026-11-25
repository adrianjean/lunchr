import AppKit
import ServiceManagement
import SwiftUI
import LunchrCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State var tab = 0
    @State private var showPreview = true
    let preview: (Bool) -> Void

    private var previewing: Bool { showPreview && (tab == 1 || tab == 2) }

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(state: state).tabItem { Text("General") }.tag(0)
            AppearanceTab(state: state, showPreview: $showPreview).tabItem { Text("Appearance") }.tag(1)
            ThemesTab(state: state, showPreview: $showPreview).tabItem { Text("Themes") }.tag(2)
            MemoryTab(state: state).tabItem { Text("Remembered") }.tag(3)
            AppsTab(state: state).tabItem { Text("Apps") }.tag(4)
        }
        .padding(12)
        .frame(width: 680, height: 580)
        .onChange(of: tab, initial: true) {
            state.editingThemeID = tab == 2 ? state.activeThemeID : nil
        }
        .onChange(of: previewing, initial: true) { preview(previewing) }
    }
}

private struct GeneralTab: View {
    @ObservedObject var state: AppState
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var spotlight = SpotlightShortcut.current

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") { HotKeyRecorder(state: state) }
                if state.hotKeyFailed {
                    Label("Another app is using \(state.config.hotKey.label). Choose a different one.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if spotlight == state.config.hotKey {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spotlight also uses \(state.config.hotKey.label). Open Keyboard Shortcuts › Spotlight and turn off “Show Spotlight search”.")
                        Button("Open Keyboard Settings") { SpotlightShortcut.openSettings() }
                    }
                } else if state.config.hotKey != .commandSpace {
                    Button("Use ⌘Space instead") { state.config.hotKey = .commandSpace }
                }
            }
            Section {
                Toggle("Open at login", isOn: $atLogin)
                    .onChange(of: atLogin) { _, on in setLogin(on) }
                if let loginError { Text(loginError).foregroundStyle(.red) }
                Toggle("Show recent apps before typing", isOn: $state.config.showRecents)
                Stepper("Results: \(state.config.maxResults)", value: $state.config.maxResults, in: 3...12)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            spotlight = SpotlightShortcut.current
            atLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLogin(_ on: Bool) {
        guard on != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        atLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct AppearanceTab: View {
    @ObservedObject var state: AppState
    @Binding var showPreview: Bool

    var body: some View {
        Form {
            Section("Theme") {
                picker("When the Mac is light", $state.config.lightTheme)
                picker("When the Mac is dark", $state.config.darkTheme)
                Toggle("Show launcher", isOn: $showPreview)
            }
            Section("Transparency and blur") {
                Toggle("Use the theme's transparency", isOn: Binding(
                    get: { state.config.opacity == nil },
                    set: { state.config.opacity = $0 ? nil : state.theme.opacity }))
                if state.config.opacity != nil {
                    LabeledContent("Transparency") {
                        Slider(value: Binding(
                            get: { 1 - (state.config.opacity ?? state.theme.opacity) },
                            set: { state.config.opacity = 1 - $0 }), in: 0...1)
                        Text("\(Int(((1 - state.theme.opacity) * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Blur", selection: $state.config.blur) {
                    Text("Theme's own").tag(BlurStyle?.none)
                    ForEach(BlurStyle.allCases, id: \.self) { Text($0.label).tag(BlurStyle?.some($0)) }
                }
            }
            Section {
                Picker("Reveal", selection: $state.config.reveal) {
                    Text("Off").tag(RevealStyle.off)
                    Text("Pop").tag(RevealStyle.pop)
                    Text("Pop and glow").tag(RevealStyle.glow)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func picker(_ title: String, _ id: Binding<String>) -> some View {
        Picker(title, selection: id) {
            ForEach(state.themes) { Text($0.name).tag($0.id) }
            if !state.themes.contains(where: { $0.id == id.wrappedValue }) {
                Text("\(id.wrappedValue) (missing)").tag(id.wrappedValue)
            }
        }
    }
}

private struct MemoryTab: View {
    @ObservedObject var state: AppState

    private struct Row: Identifiable {
        let query: String, path: String, pinned: Bool
        var id: String { query }
    }

    private var rows: [Row] {
        Set(state.memory.choices.keys).union(state.memory.pins.keys).sorted().compactMap { query in
            if let path = state.memory.pins[query] { return Row(query: query, path: path, pinned: true) }
            guard let path = state.memory.choices[query]?.max(by: { $0.value < $1.value })?.key else { return nil }
            return Row(query: query, path: path, pinned: false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                ContentUnavailableView(
                    "Nothing remembered yet", systemImage: "brain",
                    description: Text("Open an app from a search and it moves to the top for that search."))
            } else {
                List(rows) { row in
                    HStack {
                        Text(row.query).fontWeight(.medium).frame(width: 130, alignment: .leading).lineLimit(1)
                        Image(nsImage: state.icon(row.path)).resizable().frame(width: 18, height: 18)
                        Text(state.name(row.path)).lineLimit(1)
                        Spacer()
                        Button {
                            state.updateMemory {
                                if row.pinned { $0.unpin(row.query) } else { $0.pin(row.path, query: Query(row.query)) }
                            }
                        } label: { Image(systemName: row.pinned ? "pin.fill" : "pin") }
                            .help(row.pinned ? "Unpin" : "Always first for this search")
                        Button { state.updateMemory { $0.forget(row.query) } } label: { Image(systemName: "xmark") }
                            .help("Forget")
                    }
                    .buttonStyle(.borderless)
                }
                HStack {
                    Spacer()
                    Button("Forget Everything", role: .destructive) { confirmForget() }
                }
                .padding(12)
            }
        }
    }

    private func confirmForget() {
        let alert = NSAlert()
        alert.messageText = "Forget every remembered search?"
        alert.informativeText = "Pins and recent apps are cleared too."
        alert.addButton(withTitle: "Forget Everything").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { state.updateMemory { $0.forgetAll() } }
    }
}

private struct AppsTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("Hidden apps") {
                if state.config.hidden.isEmpty {
                    Text("None. Press ⌘H on a result to hide it.").foregroundStyle(.secondary)
                }
                ForEach(state.config.hidden, id: \.self) { path in
                    LabeledContent(state.name(path)) { Button("Show") { state.setHidden(path, false) } }
                }
            }
            Section("Extra folders to look in") {
                ForEach(state.config.extraFolders, id: \.self) { path in
                    LabeledContent(path) {
                        Button("Remove") { state.config.extraFolders.removeAll { $0 == path } }
                    }
                }
                Button("Add Folder…") { addFolder() }
            }
            Section {
                LabeledContent("\(state.apps.count) apps found") { Button("Rescan") { state.rescan() } }
            }
        }
        .formStyle(.grouped)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let path = panel.url?.path,
              !state.config.extraFolders.contains(path) else { return }
        state.config.extraFolders.append(path)
    }
}

/// Click, press a shortcut. Escape cancels.
private struct HotKeyRecorder: View {
    @ObservedObject var state: AppState
    @State private var monitor: Any?

    var body: some View {
        Button(monitor == nil ? state.config.hotKey.label : "Press a shortcut…") {
            monitor == nil ? start() : stop()
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start() {
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
            } else if let key = HotKey(event: event) {
                state.config.hotKey = key
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        state.registerHotKey()
    }
}
