import SwiftUI
import LunchrCore

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var state: AppState

    var body: some View {
        let theme = state.theme
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .circular)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: theme.querySize * 0.8, weight: .medium))
                    .foregroundStyle(theme.secondaryText.color)
                    .frame(width: theme.iconSize)
                    .modifier(RevealIn(
                        model: model, animation: .spring(duration: 0.4, bounce: 0.45), scale: 0.4, degrees: -35))
                    .id(model.revealID)
                    .accessibilityHidden(true)
                QueryField(model: model, theme: theme)
            }
            .padding(.horizontal, 18)
            .frame(height: theme.fieldHeight)

            if !model.results.isEmpty {
                theme.border.color.frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { i, item in
                        row(i, item, theme)
                    }
                }
                .id(model.revealID)
                .padding(Theme.listPadding)
            }
            Spacer(minLength: 0)
        }
        .frame(width: theme.width)
        .background(theme.background.color.opacity(theme.opacity))
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.border.color, lineWidth: 1))
        .environment(\.colorScheme, theme.dark ? .dark : .light)
    }

    private func row(_ i: Int, _ item: RankedApp, _ theme: Theme) -> some View {
        let selected = i == model.selection
        return HStack(spacing: 12) {
            Image(nsImage: state.icon(item.app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: theme.iconSize, height: theme.iconSize)
                .accessibilityHidden(true)
            Text(highlighted(item, theme, selected))
                .lineLimit(1)
            Spacer(minLength: 8)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: theme.rowSize * 0.75))
                    .foregroundStyle(theme.accent.color)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: max(4, theme.cornerRadius - Theme.listPadding), style: .circular)
                .fill(selected ? theme.selection.color : .clear))
        .modifier(RevealIn(
            model: model, animation: .spring(duration: 0.3, bounce: 0.2).delay(0.02 + Double(i) * 0.022),
            opacity: 0, offset: 14))
        .contentShape(Rectangle())
        .onContinuousHover { phase in if case .active = phase { model.hover(i) } }
        .onTapGesture { model.open(i) }
        .contextMenu {
            Button("Open") { model.open(i) }
            if !Query(model.query).isEmpty {
                if item.isPinned {
                    Button("Unpin from “\(model.query)”") { model.unpin() }
                } else {
                    Button("Open and Pin to “\(model.query)”") { model.open(i, pin: true) }
                }
            }
            Divider()
            Button("Hide from Lunchr") { model.hide(i) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func highlighted(_ item: RankedApp, _ theme: Theme, _ selected: Bool) -> AttributedString {
        let marked = Set(item.indices)
        var result = AttributedString()
        for (i, c) in item.app.name.enumerated() {
            var piece = AttributedString(String(c))
            let hit = marked.contains(i)
            piece.font = theme.font(theme.rowSize, hit ? .semibold : .regular)
            piece.foregroundColor = hit ? theme.accent.color : (selected ? theme.selectedText.color : theme.text.color)
            result += piece
        }
        return result
    }
}

/// Animates a view in if it was created during a reveal.
private struct RevealIn: ViewModifier {
    let animation: Animation
    let scale: Double
    let degrees: Double
    let opacity: Double
    let offset: Double
    @State private var shown: Bool

    @MainActor
    init(
        model: LauncherModel, animation: Animation,
        scale: Double = 1, degrees: Double = 0, opacity: Double = 1, offset: Double = 0
    ) {
        self.animation = animation
        self.scale = scale
        self.degrees = degrees
        self.opacity = opacity
        self.offset = offset
        _shown = State(initialValue: !model.isRevealing)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : scale)
            .rotationEffect(.degrees(shown ? 0 : degrees))
            .opacity(shown ? 1 : opacity)
            .offset(y: shown ? 0 : offset)
            .onAppear {
                guard !shown else { return }
                withAnimation(animation) { shown = true }
            }
    }
}

/// AppKit field: SwiftUI's can't take focus reliably in a panel that doesn't activate its app.
struct QueryField: NSViewRepresentable {
    @ObservedObject var model: LauncherModel
    let theme: Theme

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.identifier = LauncherPanel.fieldID
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search apps")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.query { field.stringValue = model.query }
        let font = theme.nsFont(theme.querySize)
        if field.font != font { field.font = font }
        field.textColor = theme.text.nsColor
        field.placeholderAttributedString = NSAttributedString(
            string: "Open an app",
            attributes: [.foregroundColor: theme.secondaryText.nsColor, .font: font])
        (field.currentEditor() as? NSTextView)?.insertionPointColor = theme.accent.nsColor
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let model: LauncherModel
        init(_ model: LauncherModel) { self.model = model }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            model.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)): model.move(1)
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)): model.move(-1)
            case #selector(NSResponder.insertNewline(_:)): model.open()
            case #selector(NSResponder.cancelOperation(_:)): model.onClose?()
            default: return false
            }
            return true
        }
    }
}
