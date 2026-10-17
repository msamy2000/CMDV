import Foundation
import SwiftUI
import AppKit

@MainActor
public final class PopupViewModel: ObservableObject {
    @Published public var selectedIndex: Int = 0
    @Published public var hoveredDeleteItemID: UUID? = nil

    public let store: HistoryStore
    public let onSelectItem: (ClipboardItem, SelectionActionMode) -> Void
    public let onDeleteItem: (ClipboardItem) -> Void

    public init(
        store: HistoryStore,
        onSelectItem: @escaping (ClipboardItem, SelectionActionMode) -> Void,
        onDeleteItem: @escaping (ClipboardItem) -> Void
    ) {
        self.store = store
        self.onSelectItem = onSelectItem
        self.onDeleteItem = onDeleteItem
    }

    public func resetSelection() {
        selectedIndex = 0
        hoveredDeleteItemID = nil
    }

    public func moveSelection(delta: Int) {
        let count = store.items.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    public func triggerSelected(mode: SelectionActionMode) {
        guard store.items.indices.contains(selectedIndex) else { return }
        let item = store.items[selectedIndex]
        onSelectItem(item, mode)
    }

    public func triggerQuickIndex(_ index: Int, mode: SelectionActionMode) {
        guard store.items.indices.contains(index) else { return }
        selectedIndex = index
        onSelectItem(store.items[index], mode)
    }

    public func deleteSelected() {
        guard store.items.indices.contains(selectedIndex) else { return }
        let item = store.items[selectedIndex]
        onDeleteItem(item)
        if selectedIndex >= store.items.count {
            selectedIndex = max(0, store.items.count - 1)
        }
    }
}

public struct PopupContentView: View {
    @ObservedObject var viewModel: PopupViewModel
    @ObservedObject var store: HistoryStore

    public init(viewModel: PopupViewModel) {
        self.viewModel = viewModel
        self.store = viewModel.store
    }

    public var body: some View {
        ZStack {
            VisualEffectMaterialView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            if store.items.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                                ClipboardCardView(
                                    item: item,
                                    index: index,
                                    isSelected: index == viewModel.selectedIndex,
                                    isDeleteHovered: viewModel.hoveredDeleteItemID == item.id,
                                    imageData: store.loadImageData(for: item),
                                    onHoverChange: { hovering in
                                        if hovering {
                                            viewModel.selectedIndex = index
                                        }
                                    },
                                    onDeleteHoverChange: { hovering in
                                        if hovering {
                                            viewModel.hoveredDeleteItemID = item.id
                                        } else if viewModel.hoveredDeleteItemID == item.id {
                                            viewModel.hoveredDeleteItemID = nil
                                        }
                                    },
                                    onSelect: { mode in
                                        viewModel.selectedIndex = index
                                        viewModel.onSelectItem(item, mode)
                                    },
                                    onDelete: {
                                        viewModel.onDeleteItem(item)
                                        if viewModel.selectedIndex >= store.items.count {
                                            viewModel.selectedIndex = max(0, store.items.count - 1)
                                        }
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        guard store.items.indices.contains(newIndex) else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(store.items[newIndex].id, anchor: nil)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: computedHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }

    private var computedHeight: CGFloat {
        if store.items.isEmpty {
            return 130
        }
        return 430
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("Clipboard is empty")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Copy text, images, or files to see up to 20 items (5 days).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let isDeleteHovered: Bool
    let imageData: Data?
    let onHoverChange: (Bool) -> Void
    let onDeleteHoverChange: (Bool) -> Void
    let onSelect: (SelectionActionMode) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Card Content Area (Text, Image, File, or Binary)
            cardContentBody

            // Subtle metadata bar at bottom of card
            HStack(spacing: 6) {
                kindBadge
                if let appName = item.sourceAppName, !appName.isEmpty {
                    Text("• \(appName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("• \(item.relativeTimeString())")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.07))
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1.0
                )
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isDeleteHovered ? Color.white : Color.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(isDeleteHovered ? Color.red.opacity(0.85) : Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(7)
            .onHover { hovering in
                onDeleteHoverChange(hovering)
            }
            .help("Delete item (⌥⌫)")
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            onHoverChange(hovering)
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.option) && flags.contains(.shift) {
                onSelect(.pastePlainText)
            } else if flags.contains(.option) {
                onSelect(.copyOnly)
            } else {
                onSelect(.autoPaste)
            }
        }
    }

    @ViewBuilder
    private var cardContentBody: some View {
        switch item.kind {
        case .image:
            if let data = imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 115)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.trailing, 22)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text(item.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                }
                .padding(.trailing, 22)
            }

        case .file:
            HStack(spacing: 10) {
                if let data = imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                    if let firstPath = item.fileURLs.first {
                        Text(firstPath)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.trailing, 22)

        case .text:
            Text(item.displayTitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 22)

        case .binary:
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text(item.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
            }
            .padding(.trailing, 22)
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        switch item.kind {
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight, w > 0, h > 0 {
                Label("\(w)×\(h)", systemImage: "photo")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Label("Image", systemImage: "photo")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .file:
            Label(item.fileURLs.count > 1 ? "\(item.fileURLs.count) files" : "File", systemImage: "folder")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .text:
            Label("Text", systemImage: "text.alignleft")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .binary:
            Label("Binary", systemImage: "doc.zipper")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct VisualEffectMaterialView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
