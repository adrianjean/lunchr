import AppKit
import Combine
import LunchrCore

/// What the launcher window is showing right now.
@MainActor
final class LauncherModel: ObservableObject {
    let state: AppState
    @Published var query = "" { didSet { if query != oldValue { refresh(resetSelection: true) } } }
    @Published private(set) var results: [RankedApp] = []
    @Published var selection = 0
    /// Changes with every reveal, so rows start fresh instead of resuming an interrupted animation.
    @Published private(set) var revealID = 0
    /// Views created while this is true animate in; later ones (typing) are in place at once.
    private(set) var isRevealing = false
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private var mouseAtOpen = NSPoint.zero
    private var subscriptions: Set<AnyCancellable> = []

    init(state: AppState) {
        self.state = state
        // @Published fires before the value is set, so read it on the next turn.
        Publishers.Merge3(
            state.$apps.map { _ in () }, state.$config.map { _ in () }, state.$memory.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh(resetSelection: false) }
            .store(in: &subscriptions)
    }

    func reset() {
        mouseAtOpen = NSEvent.mouseLocation
        query = ""
        refresh(resetSelection: true)
    }

    func beginReveal() {
        isRevealing = true
        revealID += 1
    }

    func endReveal() { isRevealing = false }

    private func refresh(resetSelection: Bool) {
        results = state.search(query)
        selection = resetSelection ? 0 : min(selection, max(0, results.count - 1))
    }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + step + results.count) % results.count
    }

    /// A list that appears under a resting pointer shouldn't change the selection.
    func hover(_ index: Int) {
        guard NSEvent.mouseLocation != mouseAtOpen else { return }
        mouseAtOpen = NSEvent.mouseLocation
        selection = index
    }

    func open(_ index: Int? = nil, pin: Bool = false) {
        let i = index ?? selection
        guard results.indices.contains(i) else { return }
        let app = results[i].app
        let typed = Query(query)
        onClose?()
        state.updateMemory {
            $0.recordLaunch(app.path, query: typed)
            if pin { $0.pin(app.path, query: typed) }
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: options) { [weak self] _, error in
            guard let error else { return }
            let message = error.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.state.rescan()
                    let alert = NSAlert()
                    alert.messageText = "\(app.name) couldn't be opened"
                    alert.informativeText = message
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
    }

    func unpin() { state.updateMemory { $0.unpin(Query(query).key) } }

    func hide(_ index: Int? = nil) {
        let i = index ?? selection
        guard results.indices.contains(i) else { return }
        state.setHidden(results[i].app.path, true)
    }
}
