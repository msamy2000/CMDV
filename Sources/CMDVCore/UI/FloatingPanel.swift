import Foundation
import AppKit
import SwiftUI
import Carbon

@MainActor
public final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private let store: HistoryStore
    private let pasteService: PasteService
    private let viewModel: PopupViewModel
    private var previousApp: NSRunningApplication?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public init(store: HistoryStore, pasteService: PasteService) {
        self.store = store
        self.pasteService = pasteService

        var vmRef: PopupViewModel?
        let vm = PopupViewModel(
            store: store,
            onSelectItem: { _, _ in },
            onDeleteItem: { _ in }
        )
        self.viewModel = vm
        super.init()

        // Rebind viewModel closures cleanly with weak self
        let boundVM = PopupViewModel(
            store: store,
            onSelectItem: { [weak self] item, mode in
                self?.handleItemSelection(item: item, mode: mode)
            },
            onDeleteItem: { [weak self] item in
                self?.store.remove(id: item.id)
                self?.resizePanelForCurrentContent()
            }
        )
        vmRef = boundVM
        _ = vmRef
        self.setupPanel(with: boundVM)
    }

    private var activeViewModel: PopupViewModel?

    private func setupPanel(with vm: PopupViewModel) {
        self.activeViewModel = vm
        let rootView = PopupContentView(viewModel: vm)
        let hostingView = NSHostingView(rootView: rootView)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 430),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = hostingView
        panel.delegate = self

        self.panel = panel
    }

    /// Toggles the popup at the active text caret or mouse cursor (when triggered by `Cmd+Shift+V`).
    public func toggleAtCursorOrCaret() {
        if isVisible {
            closePanel(restoreFocus: true)
        } else {
            let anchor = CursorPositionHelper.currentCaretOrMouseScreenPoint()
            showPanel(atAnchor: anchor, preferBelow: true)
        }
    }

    /// Toggles the popup anchored directly below the menu bar status item button.
    public func toggleAnchored(toStatusButton button: NSStatusBarButton?) {
        if isVisible {
            closePanel(restoreFocus: true)
            return
        }
        if let buttonWindow = button?.window {
            let buttonFrame = buttonWindow.frame
            let anchor = NSPoint(x: buttonFrame.minX, y: buttonFrame.minY)
            showPanel(atAnchor: anchor, preferBelow: true)
        } else {
            toggleAtCursorOrCaret()
        }
    }

    public func showPanel(atAnchor anchor: NSPoint, preferBelow: Bool) {
        guard let panel = panel, let vm = activeViewModel else { return }

        // Capture currently active application before showing popup so we can paste directly into it
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousApp = front
        }

        store.purgeExpired(now: Date())
        vm.resetSelection()

        let targetSize = NSSize(width: 360, height: store.items.isEmpty ? 130 : 430)
        let origin = CursorPositionHelper.clampedWindowOrigin(
            anchor: anchor,
            windowSize: targetSize,
            preferBelow: preferBelow
        )
        panel.setFrame(NSRect(origin: origin, size: targetSize), display: true)

        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }

    public func closePanel(restoreFocus: Bool) {
        removeEventMonitors()
        panel?.orderOut(nil)
        if restoreFocus,
           let app = previousApp,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate()
        }
    }

    private func resizePanelForCurrentContent() {
        guard let panel = panel, panel.isVisible else { return }
        let newHeight: CGFloat = store.items.isEmpty ? 130 : 430
        var frame = panel.frame
        let heightDelta = frame.height - newHeight
        frame.origin.y += heightDelta
        frame.size.height = newHeight
        panel.setFrame(frame, display: true, animate: true)
    }

    private func handleItemSelection(item: ClipboardItem, mode: SelectionActionMode) {
        let targetApp = self.previousApp
        pasteService.performAction(
            for: item,
            mode: mode,
            targetApp: targetApp,
            afterClosingPanel: { [weak self] in
                self?.removeEventMonitors()
                self?.panel?.orderOut(nil)
            }
        )
    }

    // MARK: - Event Monitors (Keyboard Navigation & Outside Click Dismiss)

    private func installEventMonitors() {
        removeEventMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanel(restoreFocus: false)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalClickMonitor = globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let vm = activeViewModel else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        // Escape (53) -> Close panel
        if keyCode == kVK_Escape {
            closePanel(restoreFocus: true)
            return true
        }

        // Up Arrow (126) or Ctrl+P
        if keyCode == kVK_UpArrow || (flags == .control && keyCode == kVK_ANSI_P) {
            vm.moveSelection(delta: -1)
            return true
        }

        // Down Arrow (125) or Ctrl+N
        if keyCode == kVK_DownArrow || (flags == .control && keyCode == kVK_ANSI_N) {
            vm.moveSelection(delta: 1)
            return true
        }

        // Option + Delete (51) or Forward Delete (117) -> Delete selected item
        if (keyCode == kVK_Delete && flags.contains(.option)) || keyCode == kVK_ForwardDelete {
            vm.deleteSelected()
            resizePanelForCurrentContent()
            return true
        }

        // Return (36) or Keypad Enter (76)
        if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            if flags.contains(.option) && flags.contains(.shift) {
                vm.triggerSelected(mode: .pastePlainText)
            } else if flags.contains(.option) {
                vm.triggerSelected(mode: .copyOnly)
            } else {
                vm.triggerSelected(mode: .autoPaste)
            }
            return true
        }

        // Cmd+1..9 or Option+1..9 quick shortcuts
        if let numberIndex = Self.numberShortcutIndex(forKeyCode: keyCode),
           flags.contains(.command) || flags.contains(.option) {
            let mode: SelectionActionMode
            if flags.contains(.option) && flags.contains(.shift) {
                mode = .pastePlainText
            } else if flags.contains(.option) && !flags.contains(.command) {
                mode = .copyOnly
            } else {
                mode = .autoPaste
            }
            vm.triggerQuickIndex(numberIndex, mode: mode)
            return true
        }

        return false
    }

    public func windowDidResignKey(_ notification: Notification) {
        closePanel(restoreFocus: false)
    }

    private static func numberShortcutIndex(forKeyCode keyCode: Int) -> Int? {
        switch keyCode {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }
}

public final class FloatingPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}
