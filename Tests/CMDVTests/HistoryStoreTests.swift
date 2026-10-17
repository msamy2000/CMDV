import Foundation
import AppKit
import CMDVCore

enum TestError: Error, CustomStringConvertible {
    case assertionFailed(String)

    var description: String {
        switch self {
        case .assertionFailed(let msg): return "Assertion Failed: \(msg)"
        }
    }
}

func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) throws {
    if !condition() {
        throw TestError.assertionFailed("\(message) (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if actual != expected {
        throw TestError.assertionFailed("\(message) — Expected \(expected), got \(actual) (\(file):\(line))")
    }
}

@MainActor
struct HistoryStoreTestSuite {
    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CMDVTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func testLoopOverwriteAt20Items() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = HistoryStore(maxItems: 20, maxAgeSeconds: 5 * 86400, storageDirectory: dir, startBackgroundTimer: false)
        let baseDate = Date()

        // Insert 25 distinct text items
        for i in 1...25 {
            let item = ClipboardItem.makeText("Item #\(i)", createdAt: baseDate.addingTimeInterval(Double(i)))
            store.add(item, now: baseDate.addingTimeInterval(Double(i)))
        }

        try assertEqual(store.items.count, 20, "Store must cap history strictly at 20 items via loop overwrite")
        try assertEqual(store.items.first?.textContent, "Item #25", "Newest item (#25) must be at index 0")
        try assertEqual(store.items.last?.textContent, "Item #6", "Oldest surviving item must be #6 (items #1..#5 overwritten)")
    }

    static func testFiveDayExpiration() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fiveDays: TimeInterval = 5 * 24 * 60 * 60
        let store = HistoryStore(maxItems: 20, maxAgeSeconds: fiveDays, storageDirectory: dir, startBackgroundTimer: false)
        let t0 = Date()

        // Add an item at t0
        let oldItem = ClipboardItem.makeText("Old 6-day item", createdAt: t0)
        store.add(oldItem, now: t0)

        // Add another item at t0 + 2 days
        let twoDaysLater = t0.addingTimeInterval(2 * 86400)
        let midItem = ClipboardItem.makeText("Mid 4-day item", createdAt: twoDaysLater)
        store.add(midItem, now: twoDaysLater)

        // Now advance clock to t0 + 6 days (oldItem is 6 days old > 5d; midItem is 4 days old <= 5d)
        let sixDaysLater = t0.addingTimeInterval(6 * 86400)
        let freshItem = ClipboardItem.makeText("Fresh item", createdAt: sixDaysLater)
        store.add(freshItem, now: sixDaysLater)

        try assertEqual(store.items.count, 2, "6-day-old item must be automatically purged when 5-day threshold is reached")
        try assertEqual(store.items[0].textContent, "Fresh item")
        try assertEqual(store.items[1].textContent, "Mid 4-day item")
    }

    static func testDeduplicationAndTimerReset() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fiveDays: TimeInterval = 5 * 86400
        let store = HistoryStore(maxItems: 20, maxAgeSeconds: fiveDays, storageDirectory: dir, startBackgroundTimer: false)
        let t0 = Date()

        store.add(ClipboardItem.makeText("Alpha", createdAt: t0), now: t0)
        store.add(ClipboardItem.makeText("Beta", createdAt: t0.addingTimeInterval(60)), now: t0.addingTimeInterval(60))

        // Re-copy "Alpha" 4 days later -> should move to index 0 and reset its 5-day TTL
        let fourDaysLater = t0.addingTimeInterval(4 * 86400)
        store.add(ClipboardItem.makeText("Alpha", createdAt: fourDaysLater), now: fourDaysLater)

        try assertEqual(store.items.count, 2, "Re-copying Alpha must deduplicate instead of creating a 3rd entry")
        try assertEqual(store.items[0].textContent, "Alpha", "Deduplicated Alpha must move to index 0")
        try assertEqual(store.items[1].textContent, "Beta")

        // Advance to t0 + 6 days: Beta is now ~6 days old (expired), while Alpha was refreshed at t0 + 4d (only 2 days old!)
        let sixDaysLater = t0.addingTimeInterval(6 * 86400)
        let purged = store.purgeExpired(now: sixDaysLater)

        try assertEqual(purged, 1, "Beta should expire at day 6 while refreshed Alpha survives")
        try assertEqual(store.items.count, 1)
        try assertEqual(store.items[0].textContent, "Alpha")
    }

    static func testBinaryImageAndDiskPersistence() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = HistoryStore(maxItems: 20, maxAgeSeconds: 5 * 86400, storageDirectory: dir, startBackgroundTimer: false)

        // Create a synthetic 128 KB binary image payload (> 64KB inline threshold so it spills to Payloads/ on disk)
        let binaryPNG = Data((0..<(128 * 1024)).map { UInt8($0 & 0xFF) })
        let imageItem = ClipboardItem.makeImage(pngData: binaryPNG, width: 400, height: 300)
        store.add(imageItem)

        try assertEqual(store.items.count, 1)
        try assertEqual(store.items[0].kind, .image)
        try assertTrue(!store.items[0].payloadFiles.isEmpty, "Large binary payload (>64KB) should be stored in external payload file")

        // Reload a fresh HistoryStore instance pointing at the same directory to verify persistence
        let reloadedStore = HistoryStore(maxItems: 20, maxAgeSeconds: 5 * 86400, storageDirectory: dir, startBackgroundTimer: false)
        try assertEqual(reloadedStore.items.count, 1, "Reloaded store must restore persisted items")
        let restoredPayloads = reloadedStore.loadAllPayloads(for: reloadedStore.items[0])
        try assertEqual(restoredPayloads["public.png"], binaryPNG, "Restored binary PNG bytes must match bit-for-bit")
    }

    static func testConcealedClipboardIgnored() throws {
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("SuperSecretPassword123", forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.writeObjects([item])

        let extracted = ClipboardMonitor.extractItem(from: pb)
        try assertTrue(extracted == nil, "Concealed password-manager items must be ignored")
    }

    static func testWhicheverReachedFirstMixedLimits() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fiveDays: TimeInterval = 5 * 86400
        let store = HistoryStore(maxItems: 20, maxAgeSeconds: fiveDays, storageDirectory: dir, startBackgroundTimer: false)
        let t0 = Date()

        // Insert 10 items at t0 (which will expire after 5 days)
        for i in 1...10 {
            store.add(ClipboardItem.makeText("Early-\(i)", createdAt: t0.addingTimeInterval(Double(i))), now: t0.addingTimeInterval(Double(i)))
        }
        try assertEqual(store.items.count, 10)

        // At t0 + 3 days, insert 15 more items -> total would be 25, so 20-item limit reached first (evicts Early-1..Early-5)
        let day3 = t0.addingTimeInterval(3 * 86400)
        for i in 1...15 {
            let ts = day3.addingTimeInterval(Double(i))
            store.add(ClipboardItem.makeText("Mid-\(i)", createdAt: ts), now: ts)
        }
        try assertEqual(store.items.count, 20, "20-item limit reached first at Day 3")
        try assertEqual(store.items.last?.textContent, "Early-6")

        // At t0 + 6 days, the remaining Early-6..Early-10 items cross the 5-day age limit (6d > 5d), while Mid-1..Mid-15 are 3d old
        let day6 = t0.addingTimeInterval(6 * 86400)
        let purgedCount = store.purgeExpired(now: day6)
        try assertEqual(purgedCount, 5, "5-day limit reached for Early-6..Early-10 at Day 6")
        try assertEqual(store.items.count, 15)
        try assertEqual(store.items.last?.textContent, "Mid-1")
    }

    static func testPasteServiceRestoresTextAndBinaryPayloads() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pb = NSPasteboard.withUniqueName()
        let store = HistoryStore(maxItems: 20, maxAgeSeconds: 5 * 86400, storageDirectory: dir, startBackgroundTimer: false)
        let monitor = ClipboardMonitor(pasteboard: pb, store: store)
        let pasteService = PasteService(store: store, monitor: monitor, pasteboard: pb)

        // 1. Rich text + custom binary payload
        let customBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x42])
        let richItem = ClipboardItem(
            kind: .text,
            textContent: "Rich Hello",
            byteSize: customBytes.count,
            contentHash: "hash-rich-1",
            inlinePayloads: [
                NSPasteboard.PasteboardType.string.rawValue: Data("Rich Hello".utf8),
                "com.cmdv.custom-binary": customBytes
            ]
        )
        store.add(richItem)

        // Write full payloads back to pasteboard
        pasteService.writeToPasteboard(item: store.items[0], plainTextOnly: false)
        try assertEqual(pb.string(forType: .string), "Rich Hello")
        try assertEqual(pb.data(forType: NSPasteboard.PasteboardType("com.cmdv.custom-binary")), customBytes)

        // Verify monitor ignores self-generated pasteboard write
        monitor.checkForChanges()
        try assertEqual(store.items.count, 1)

        // Write plain-text-only mode (Option+Shift+Enter)
        pasteService.writeToPasteboard(item: store.items[0], plainTextOnly: true)
        try assertEqual(pb.string(forType: .string), "Rich Hello")
        try assertTrue(pb.data(forType: NSPasteboard.PasteboardType("com.cmdv.custom-binary")) == nil, "Plain-text paste must strip non-string binary types")
    }
}
