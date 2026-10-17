import Foundation
import Combine

@MainActor
public final class HistoryStore: ObservableObject {
    public nonisolated static let defaultMaxItems: Int = 20
    public nonisolated static let defaultMaxAgeSeconds: TimeInterval = 5 * 24 * 60 * 60 // 5 days = 432,000s

    /// Threshold above which individual pasteboard type payloads are spilled to dedicated files on disk
    private static let inlineByteThreshold: Int = 64 * 1024 // 64 KB

    @Published public private(set) var items: [ClipboardItem] = []

    public let maxItems: Int
    public let maxAgeSeconds: TimeInterval
    public let storageDirectory: URL

    private let indexFileURL: URL
    private let payloadsDirectoryURL: URL
    private var expirationTimer: Timer?

    public init(
        maxItems: Int = HistoryStore.defaultMaxItems,
        maxAgeSeconds: TimeInterval = HistoryStore.defaultMaxAgeSeconds,
        storageDirectory: URL? = nil,
        startBackgroundTimer: Bool = true
    ) {
        self.maxItems = maxItems
        self.maxAgeSeconds = maxAgeSeconds

        if let customDir = storageDirectory {
            self.storageDirectory = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageDirectory = appSupport.appendingPathComponent("CMDV", isDirectory: true)
        }

        self.indexFileURL = self.storageDirectory.appendingPathComponent("history.json", isDirectory: false)
        self.payloadsDirectoryURL = self.storageDirectory.appendingPathComponent("Payloads", isDirectory: true)

        ensureDirectoriesExist()
        loadFromDisk()
        purgeExpired(now: Date())

        if startBackgroundTimer {
            startExpirationTimer()
        }
    }

    deinit {
        expirationTimer?.invalidate()
    }

    private func ensureDirectoriesExist() {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: payloadsDirectoryURL, withIntermediateDirectories: true)
    }

    private func startExpirationTimer() {
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeExpired(now: Date())
            }
        }
    }

    /// Adds a clipboard item to the top of the history, deduplicating if identical content already exists,
    /// enforcing the 5-day TTL and 20-item loop overwrite limit.
    public func add(_ incomingItem: ClipboardItem, now: Date? = nil) {
        let referenceNow = now ?? incomingItem.createdAt
        var changed = purgeExpiredInternal(now: referenceNow)

        // Check for duplicate by contentHash
        if let existingIndex = items.firstIndex(where: { $0.contentHash == incomingItem.contentHash }) {
            let removed = items.remove(at: existingIndex)
            deletePayloadFiles(for: removed)
            changed = true
        }

        // Spill large inline payloads to disk so history.json stays fast and lightweight
        let storedItem = externalizeLargePayloads(for: incomingItem)
        items.insert(storedItem, at: 0)
        changed = true

        // Enforce 20-item loop overwrite (evict oldest items past maxItems)
        while items.count > maxItems {
            let evicted = items.removeLast()
            deletePayloadFiles(for: evicted)
        }

        if changed {
            saveToDisk()
        }
    }

    /// Moves an existing item to the top of the history (e.g. when selected for paste) and resets its 5-day timer.
    public func touch(_ itemID: UUID, now: Date = Date()) {
        _ = purgeExpiredInternal(now: now)
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items.remove(at: index)
        item.createdAt = now
        items.insert(item, at: 0)
        saveToDisk()
    }

    /// Deletes a specific item from history and removes its binary payload files.
    public func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        deletePayloadFiles(for: removed)
        saveToDisk()
    }

    /// Clears all clipboard history and wipes all binary payloads on disk.
    public func clearAll() {
        for item in items {
            deletePayloadFiles(for: item)
        }
        items.removeAll()
        try? FileManager.default.removeItem(at: payloadsDirectoryURL)
        ensureDirectoriesExist()
        saveToDisk()
    }

    /// Purges any items older than `maxAgeSeconds` (5 days) or beyond `maxItems` (20 items).
    @discardableResult
    public func purgeExpired(now: Date = Date()) -> Int {
        let beforeCount = items.count
        if purgeExpiredInternal(now: now) {
            saveToDisk()
        }
        return beforeCount - items.count
    }

    private func purgeExpiredInternal(now: Date) -> Bool {
        var modified = false
        var validItems: [ClipboardItem] = []
        validItems.reserveCapacity(min(items.count, maxItems))

        for item in items {
            let age = now.timeIntervalSince(item.createdAt)
            if age > maxAgeSeconds {
                deletePayloadFiles(for: item)
                modified = true
            } else {
                validItems.append(item)
            }
        }

        while validItems.count > maxItems {
            let evicted = validItems.removeLast()
            deletePayloadFiles(for: evicted)
            modified = true
        }

        if modified {
            items = validItems
        }
        return modified
    }

    /// Resolves all pasteboard type payloads (combining inline data and external binary files on disk) for pasting.
    public func loadAllPayloads(for item: ClipboardItem) -> [String: Data] {
        var result = item.inlinePayloads
        for (pasteboardType, filename) in item.payloadFiles {
            let fileURL = payloadsDirectoryURL.appendingPathComponent(filename)
            if let data = try? Data(contentsOf: fileURL) {
                result[pasteboardType] = data
            }
        }
        return result
    }

    /// Loads image data for rendering or fallback restoration.
    public func loadImageData(for item: ClipboardItem) -> Data? {
        if let thumb = item.thumbnailPNGData {
            return thumb
        }
        let payloads = loadAllPayloads(for: item)
        if let png = payloads["public.png"] {
            return png
        }
        if let tiff = payloads["public.tiff"] {
            return tiff
        }
        return nil
    }

    // MARK: - Disk Persistence Helpers

    private func externalizeLargePayloads(for item: ClipboardItem) -> ClipboardItem {
        ensureDirectoriesExist()
        var updated = item
        var newInline: [String: Data] = [:]
        var newFiles = item.payloadFiles

        for (typeRaw, data) in item.inlinePayloads {
            if data.count > Self.inlineByteThreshold {
                let safeType = typeRaw.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: ":", with: "_")
                let filename = "\(item.id.uuidString)_\(safeType).bin"
                let fileURL = payloadsDirectoryURL.appendingPathComponent(filename)
                do {
                    try data.write(to: fileURL, options: .atomic)
                    newFiles[typeRaw] = filename
                } catch {
                    newInline[typeRaw] = data
                }
            } else {
                newInline[typeRaw] = data
            }
        }

        updated.inlinePayloads = newInline
        updated.payloadFiles = newFiles
        return updated
    }

    private func deletePayloadFiles(for item: ClipboardItem) {
        for (_, filename) in item.payloadFiles {
            let url = payloadsDirectoryURL.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func saveToDisk() {
        ensureDirectoriesExist()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            // Silently ignore write errors in rare disk-full states
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.items = try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            self.items = []
        }
    }
}
