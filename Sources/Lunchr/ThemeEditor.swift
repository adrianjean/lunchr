import AppKit
import SwiftUI
import LunchrCore

struct ThemesTab: View {
    @ObservedObject var state: AppState
    @Binding var showPreview: Bool

    private var selectedID: String { state.editingThemeID ?? state.activeThemeID }

    private var selected: Theme? { state.themes.first { $0.id == selectedID } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            Divider()
            if let theme = selected {
                ThemeForm(
                    theme: Binding(
                        get: { state.themes.first { $0.id == theme.id } ?? theme },
                        set: { state.updateTheme($0) }),
                    state: state)
                    .id(theme.id)
            } else {
                ContentUnavailableView("Choose a theme", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(
                get: { selectedID },
                set: { if let id = $0 { state.editingThemeID = id } })) {
                ForEach(state.themes) { theme in
                    HStack(spacing: 8) {
                        ThemeSwatch(theme: theme)
                        Text(theme.name.isEmpty ? theme.id : theme.name).lineLimit(1)
                        Spacer(minLength: 0)
                        if theme.id == state.activeThemeID {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                                .accessibilityLabel("In use")
                        }
                    }
                    .tag(theme.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 8) {
                Button("Use This Theme") { state.useTheme(selectedID) }
                    .disabled(selectedID == state.activeThemeID)
                Button("Duplicate") {
                    if let copy = state.duplicateTheme(selectedID) { state.editingThemeID = copy }
                }
                if ThemeLoader.isBuiltIn(selectedID) {
                    Button("Restore Original…") { confirmRemove() }.disabled(!state.hasFile(selectedID))
                } else {
                    Button("Delete…") { confirmRemove() }
                }
                Button("Open Themes Folder") { NSWorkspace.shared.open(state.themesFolder) }
                Toggle("Show launcher", isOn: $showPreview)
            }
            .padding(12)
        }
    }

    private func confirmRemove() {
        guard let theme = selected else { return }
        let builtIn = ThemeLoader.isBuiltIn(theme.id)
        let alert = NSAlert()
        alert.messageText = builtIn ? "Restore “\(theme.name)” to the original?" : "Delete “\(theme.name)”?"
        alert.informativeText = builtIn
            ? "Your version of the theme goes to the Trash." : "The theme file goes to the Trash."
        alert.addButton(withTitle: builtIn ? "Restore" : "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.removeThemeFile(theme.id)
        if !builtIn, !state.themes.contains(where: { $0.id == theme.id }) {
            state.editingThemeID = state.activeThemeID
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(theme.background.color)
            .overlay(Circle().fill(theme.accent.color).padding(5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.4)))
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

private struct ThemeForm: View {
    @Binding var theme: Theme
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            ForEach(state.themeProblems, id: \.self) {
                Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if state.config.opacity != nil || state.config.blur != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Appearance is set to override every theme's transparency or blur. The preview shows this theme's own.")
                    Button("Use Each Theme's Own") {
                        state.config.opacity = nil
                        state.config.blur = nil
                    }
                }
            }
            Section {
                TextField("Name", text: $theme.name)
                Picker("Look", selection: $theme.dark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
            }
            Section("Background") {
                ColorRow(title: "Color", color: $theme.background, allowsAlpha: false)
                SliderRow(
                    title: "Transparency",
                    value: Binding(get: { (1 - theme.opacity) * 100 }, set: { theme.opacity = 1 - $0 / 100 }),
                    range: 0...100, unit: "%")
                Picker("Blur", selection: $theme.blur) {
                    ForEach(BlurStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Colors") {
                ColorRow(title: "Text", color: $theme.text)
                ColorRow(title: "Placeholder and icon", color: $theme.secondaryText)
                ColorRow(title: "Accent", color: $theme.accent)
                ColorRow(title: "Selected row", color: $theme.selection)
                ColorRow(title: "Selected text", color: $theme.selectedText)
                ColorRow(title: "Border and line", color: $theme.border)
            }
            Section("Text") {
                Picker("Font", selection: $theme.font) {
                    Text("System").tag("system")
                    Text("Rounded").tag("rounded")
                    Text("Monospaced").tag("mono")
                    Text("Serif").tag("serif")
                    Divider()
                    ForEach(Self.families, id: \.self) { Text($0).tag($0) }
                    if !Self.standard.contains(theme.font), !Self.families.contains(theme.font) {
                        Text("\(theme.font) (not installed)").tag(theme.font)
                    }
                }
                SliderRow(title: "Search size", value: $theme.querySize, range: Theme.querySizes)
                SliderRow(title: "Result size", value: $theme.rowSize, range: Theme.rowSizes)
            }
            Section("Shape") {
                SliderRow(title: "Width", value: $theme.width, range: Theme.widths)
                SliderRow(title: "Corner radius", value: $theme.cornerRadius, range: Theme.cornerRadii)
                SliderRow(title: "Icon size", value: $theme.iconSize, range: Theme.iconSizes)
            }
        }
        .formStyle(.grouped)
    }

    private static let standard = ["system", "rounded", "mono", "serif"]
    private static let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = ""

    var body: some View {
        LabeledContent(title) {
            // Rounded here rather than with `step:`, which draws a tick for every value.
            Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range)
                .frame(minWidth: 120)
                .accessibilityLabel(title)
            Text("\(Int(value.rounded()))\(unit)")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct ColorRow: View {
    let title: String
    @Binding var color: RGBA
    var allowsAlpha = true
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        LabeledContent(title) {
            TextField("", text: $text, prompt: Text("#RRGGBB"))
                .labelsHidden()
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .focused($editing)
                .onSubmit(commit)
                .accessibilityLabel("\(title) hex")
            ColorPicker("", selection: Binding(get: { color.color }, set: pick), supportsOpacity: allowsAlpha)
                .labelsHidden()
                .accessibilityLabel(title)
        }
        .onAppear { text = color.hex }
        .onChange(of: color) { text = color.hex }
        .onChange(of: editing) { if !editing { commit() } }
    }

    /// Anything that isn't a colour goes back to the last good value.
    private func commit() {
        if var typed = RGBA(hex: text.trimmingCharacters(in: .whitespaces)) {
            if !allowsAlpha { typed.a = 1 }
            if typed != color { color = typed }
        }
        text = color.hex
    }

    private func pick(_ picked: Color) {
        guard let c = NSColor(picked).usingColorSpace(.sRGB) else { return }
        let new = RGBA(
            r: c.redComponent, g: c.greenComponent, b: c.blueComponent,
            a: allowsAlpha ? c.alphaComponent : 1)
        if new != color { color = new }
    }
}
