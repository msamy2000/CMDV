import Foundation
import AppKit
import ApplicationServices
import Carbon

public enum SelectionActionMode: Sendable {
    case autoPaste
    case copyOnly
    case pastePlainText
}

@MainActor
public final class PasteService {
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let pasteboard: NSPasteboard

    public init(
        store: HistoryStore,
        monitor: ClipboardMonitor,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.monitor = monitor
        self.pasteboard = pasteboard
    }

    /// Writes `item` back onto `NSPasteboard`, moves it to the top of the 20-item / 5-day history,
    /// and optionally synthesizes `Cmd+V` into the target application.
    public func performAction(
        for item: ClipboardItem,
        mode: SelectionActionMode,
        targetApp: NSRunningApplication?,
        afterClosingPanel: () -> Void
    ) {
        writeToPasteboard(item: item, plainTextOnly: mode == .pastePlainText)
        store.touch(item.id, now: Date())

        afterClosingPanel()

        guard mode == .autoPaste || mode == .pastePlainText else {
            return
        }

        // Reactivate the previously frontmost application and synthesize Cmd+V
        if let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
            Self.synthesizeCmdV()
        }
    }

    /// Writes the item's payloads (or stripped plain text) to the system pasteboard and tells `ClipboardMonitor`
    /// not to re-record the changeCount bump.
    public func writeToPasteboard(item: ClipboardItem, plainTextOnly: Bool) {
        pasteboard.clearContents()

        if plainTextOnly {
            let text = item.textContent ?? item.displayTitle
            pasteboard.setString(text, forType: .string)
            monitor.ignoreChangeCount(pasteboard.changeCount)
            return
        }

        // If file URLs exist, write them as NSURL objects first so Finder & file-aware apps accept them natively
        if item.kind == .file && !item.fileURLs.isEmpty {
            let nsURLs = item.fileURLs.map { NSURL(fileURLWithPath: $0) }
            pasteboard.writeObjects(nsURLs)
            monitor.ignoreChangeCount(pasteboard.changeCount)
            return
        }

        let payloads = store.loadAllPayloads(for: item)
        if !payloads.isEmpty {
            let pbItem = NSPasteboardItem()
            for (rawType, data) in payloads {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            if let text = item.textContent,
               payloads[NSPasteboard.PasteboardType.string.rawValue] == nil {
                pbItem.setString(text, forType: .string)
            }
            pasteboard.writeObjects([pbItem])
        } else if let text = item.textContent {
            pasteboard.setString(text, forType: .string)
        } else if let imgData = store.loadImageData(for: item) {
            pasteboard.setData(imgData, forType: .png)
        }

        monitor.ignoreChangeCount(pasteboard.changeCount)
    }

    /// Synthesizes `Cmd + V` (`kVK_ANSI_V = 0x09` with `.maskCommand`) via CoreGraphics HID Event Tap.
    public static func synthesizeCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Permit local modifier suppression so holding Shift/Option from Cmd+Shift+V doesn't bleed into Cmd+V
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode = CGKeyCode(kVK_ANSI_V) // 0x09

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
