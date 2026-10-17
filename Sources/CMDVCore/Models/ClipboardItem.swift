import Foundation
import AppKit
import CryptoKit

public enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
    case file
    case binary
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public let kind: ClipboardItemKind
    public let textContent: String?
    public let fileURLs: [String]
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let byteSize: Int
    public let sourceAppBundleID: String?
    public let sourceAppName: String?
    public let contentHash: String
    /// Map of PasteboardType rawValue -> relative filename in the payload directory, or inline small data
    public var payloadFiles: [String: String]
    public var inlinePayloads: [String: Data]
    /// Cached thumbnail PNG data for fast card rendering
    public var thumbnailPNGData: Data?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ClipboardItemKind,
        textContent: String? = nil,
        fileURLs: [String] = [],
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        byteSize: Int = 0,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        contentHash: String,
        payloadFiles: [String: String] = [:],
        inlinePayloads: [String: Data] = [:],
        thumbnailPNGData: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.textContent = textContent
        self.fileURLs = fileURLs
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.payloadFiles = payloadFiles
        self.inlinePayloads = inlinePayloads
        self.thumbnailPNGData = thumbnailPNGData
    }

    /// Computes a deterministic SHA-256 content hash for deduplication across text, images, files, and binary payloads.
    public static func computeHash(
        kind: ClipboardItemKind,
        text: String?,
        imageData: Data?,
        fileURLs: [String],
        fallbackData: Data? = nil
    ) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        if let text = text, !text.isEmpty {
            hasher.update(data: Data(text.utf8))
        }
        if !fileURLs.isEmpty {
            for url in fileURLs.sorted() {
                hasher.update(data: Data(url.utf8))
            }
        }
        if let imageData = imageData {
            hasher.update(data: imageData)
        } else if let fallbackData = fallbackData {
            hasher.update(data: fallbackData)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Convenience factory for unit testing and simple text creation
    public static func makeText(
        _ text: String,
        createdAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) -> ClipboardItem {
        let data = Data(text.utf8)
        let hash = computeHash(kind: .text, text: text, imageData: nil, fileURLs: [])
        return ClipboardItem(
            createdAt: createdAt,
            kind: .text,
            textContent: text,
            byteSize: data.count,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            contentHash: hash,
            inlinePayloads: [NSPasteboard.PasteboardType.string.rawValue: data]
        )
    }

    /// Convenience factory for image / binary items
    public static func makeImage(
        pngData: Data,
        width: Int,
        height: Int,
        createdAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) -> ClipboardItem {
        let hash = computeHash(kind: .image, text: nil, imageData: pngData, fileURLs: [])
        return ClipboardItem(
            createdAt: createdAt,
            kind: .image,
            imageWidth: width,
            imageHeight: height,
            byteSize: pngData.count,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            contentHash: hash,
            inlinePayloads: [NSPasteboard.PasteboardType.png.rawValue: pngData],
            thumbnailPNGData: pngData
        )
    }

    /// Human-readable summary title for accessibility or fallback display
    public var displayTitle: String {
        switch kind {
        case .text:
            let trimmed = (textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(Whitespace text)" : trimmed
        case .image:
            if let w = imageWidth, let h = imageHeight, w > 0, h > 0 {
                return "Image (\(w)×\(h))"
            }
            return "Image (\(ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)))"
        case .file:
            let names = fileURLs.map { URL(fileURLWithPath: $0).lastPathComponent }
            if names.count == 1 {
                return names[0]
            } else if names.count > 1 {
                return "\(names[0]) + \(names.count - 1) more"
            }
            return "Copied File"
        case .binary:
            if let text = textContent, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            return "Binary Data (\(ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)))"
        }
    }

    /// Human-readable relative timestamp (e.g., "Just now", "3m ago", "2d ago")
    public func relativeTimeString(relativeTo now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(createdAt)))
        if seconds < 10 {
            return "Just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h ago"
        } else {
            return "\(seconds / 86400)d ago"
        }
    }
}
