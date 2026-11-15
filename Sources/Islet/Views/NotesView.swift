import AppKit
import SwiftUI

/// Quick notes tab. A list on the left, an editor on the right.
struct NotesView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var media: MediaController
    @FocusState private var isFocused: Bool

    private var accent: Color { settings.accent(artworkTint: media.tint) }

    var body: some View {
        HStack(spacing: 10) {
            sidebar
                .frame(width: 150)
            editor
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .onChange(of: isFocused) { focused in
            state.isEditing = focused
        }
        .onChange(of: state.focusNotesRequest) { _ in
            isFocused = true
        }
        .onAppear {
            if state.focusNotesRequest > 0, state.isPinned { isFocused = true }
        }
        .onDisappear { state.isEditing = false }
    }

    private var sidebar: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(store.notes) { note in
                        row(note)
                    }
                }
            }
            Button(action: addNote) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New note")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.12)))
                .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle())
        }
    }

    private func row(_ note: Note) -> some View {
        let isSelected = note.id == store.selectedID
        return Button(action: { store.selectedID = note.id }) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(isSelected ? accent : Color.clear)
                    .frame(width: 3, height: 14)
                Text(note.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete note") { delete(note.id) }
        }
    }

    @ViewBuilder private var editor: some View {
        if let note = store.selected {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    if note.text.isEmpty {
                        Text("Type a note…")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.3))
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: store.binding(for: note.id))
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                }
                .padding(.vertical, 8)
                .padding(.leading, 6)
                .padding(.trailing, 30)

                VStack(spacing: 4) {
                    IconButton(systemName: "trash", size: 10, help: "Delete note") {
                        delete(note.id)
                    }
                    IconButton(systemName: "doc.on.doc", size: 10, help: "Copy note") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.text, forType: .string)
                    }
                }
                .padding(6)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(isFocused ? 0.5 : 0), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.2), value: isFocused)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 22))
                Text("No notes yet")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Color.white.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addNote() {
        withAnimation(settings.animation) { store.add() }
        isFocused = true
    }

    private func delete(_ id: UUID) {
        withAnimation(settings.animation) { store.delete(id) }
    }
}
