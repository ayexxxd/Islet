import AppKit
import IOKit.pwr_mgt
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Clipboard history

/// Keeps the most recent copied text snippets in memory only.
final class ClipboardManager: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var items: [Item] = []
    var limit = 12 { didSet { trim() } }

    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    func start() {
        guard timer == nil else { return }
        changeCount = NSPasteboard.general.changeCount
        let newTimer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        items.removeAll()
    }

    func copy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        changeCount = pasteboard.changeCount
        if let index = items.firstIndex(of: item), index != 0 {
            items.remove(at: index)
            items.insert(item, at: 0)
        }
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount

        // Password managers mark secrets with this type. Never record those.
        if pasteboard.types?.contains(concealedType) == true { return }
        guard let text = pasteboard.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        items.removeAll(where: { $0.text == text })
        items.insert(Item(text: text), at: 0)
        trim()
    }

    private func trim() {
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }
}

// MARK: - File shelf

/// A temporary holding spot for files dragged onto the island.
final class ShelfStore: ObservableObject {
    @Published private(set) var urls: [URL] = []
    private let key = "shelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        urls = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func add(_ url: URL) {
        guard url.isFileURL, !urls.contains(url) else { return }
        urls.append(url)
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll(where: { $0 == url })
        save()
    }

    func clear() {
        urls.removeAll()
        save()
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { [weak self] item, _ in
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                }
                guard let url = resolved else { return }
                DispatchQueue.main.async { self?.add(url) }
            }
        }
        return accepted
    }

    private func save() {
        UserDefaults.standard.set(urls.map(\.path), forKey: key)
    }
}

// MARK: - Keep awake

/// Stops the display from sleeping while switched on.
final class KeepAwake: ObservableObject {
    @Published private(set) var isOn = false
    private var assertionID: IOPMAssertionID = 0

    func toggle() {
        if isOn {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isOn = false
        } else {
            let result = IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Islet keep awake" as CFString,
                &assertionID
            )
            isOn = result == kIOReturnSuccess
        }
    }
}
