import AppKit
import SwiftUI

/// Tools tab with clipboard history and a file shelf.
struct ToolsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            if settings.clipboardEnabled {
                ClipboardCard()
            }
            if settings.shelfEnabled {
                // Takes the full width when it is the only card.
                ShelfCard()
                    .frame(width: settings.clipboardEnabled ? 230 : nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }
}

// MARK: - Clipboard

struct ClipboardCard: View {
    @EnvironmentObject var clipboard: ClipboardManager
    @EnvironmentObject var settings: AppSettings
    @State private var copiedID: UUID? = nil

    var body: some View {
        Card(title: "Clipboard") {
            if !clipboard.items.isEmpty {
                Button(action: { clipboard.clear() }) {
                    Text("Clear")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .buttonStyle(IslandButtonStyle())
            }
        } content: {
            if clipboard.items.isEmpty {
                placeholder("clipboard", "Copy some text and it shows up here")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(clipboard.items) { item in
                            row(item)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: ClipboardManager.Item) -> some View {
        let wasCopied = copiedID == item.id
        return Button(action: { copy(item) }) {
            HStack(spacing: 6) {
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: wasCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.white.opacity(wasCopied ? 0.9 : 0.35))
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(wasCopied ? 0.16 : 0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
    }

    private func copy(_ item: ClipboardManager.Item) {
        clipboard.copy(item)
        withAnimation(.easeOut(duration: 0.15)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                if copiedID == item.id { copiedID = nil }
            }
        }
    }
}

// MARK: - Shelf

struct ShelfCard: View {
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var media: MediaController

    private var accent: Color { settings.accent(artworkTint: media.tint) }
    private let columns = [GridItem(.adaptive(minimum: 42), spacing: 6)]

    var body: some View {
        Card(title: "Shelf") {
            if !shelf.urls.isEmpty {
                Button(action: { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: shelf.urls) }) {
                    Text("AirDrop")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accent)
                }
                .buttonStyle(IslandButtonStyle())
                Button(action: { withAnimation(settings.animation) { shelf.clear() } }) {
                    Text("Clear")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .buttonStyle(IslandButtonStyle())
            }
        } content: {
            if shelf.urls.isEmpty {
                placeholder("tray.and.arrow.down", "Drop files on the island to park them")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(shelf.urls, id: \.self) { url in
                            item(url)
                        }
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(state.isDropTargeted ? 0.8 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .animation(.easeOut(duration: 0.2), value: state.isDropTargeted)
    }

    private func item(_ url: URL) -> some View {
        VStack(spacing: 2) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 30, height: 30)
            Text(url.lastPathComponent)
                .font(.system(size: 8))
                .foregroundColor(Color.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 42)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .help(url.lastPathComponent)
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Remove from shelf") { withAnimation(settings.animation) { shelf.remove(url) } }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

/// Dimmed icon and caption used by empty cards.
func placeholder(_ symbol: String, _ text: String) -> some View {
    VStack(spacing: 6) {
        Image(systemName: symbol)
            .font(.system(size: 18))
        Text(text)
            .font(.system(size: 10))
            .multilineTextAlignment(.center)
    }
    .foregroundColor(Color.white.opacity(0.35))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
