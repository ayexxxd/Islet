import Foundation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var updated = Date()

    var title: String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0) }?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "New note" : firstLine
    }
}

/// Quick notes, saved as JSON in Application Support.
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID?

    private var saveWork: DispatchWorkItem?
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("Islet", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("notes.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        }
        if notes.isEmpty {
            notes = [Note(text: "Welcome to Islet\nHover the notch any time to jot something down.")]
        }
        selectedID = notes.first?.id
    }

    var selected: Note? {
        notes.first(where: { $0.id == selectedID })
    }

    func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.notes.first(where: { $0.id == id })?.text ?? "" },
            set: { [weak self] newValue in self?.update(id, text: newValue) }
        )
    }

    func add() {
        let note = Note()
        notes.insert(note, at: 0)
        selectedID = note.id
        scheduleSave()
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updated = Date()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        notes.removeAll(where: { $0.id == id })
        if selectedID == id { selectedID = notes.first?.id }
        scheduleSave()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = notes
        let url = fileURL
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
