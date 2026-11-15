import AppKit
import Combine
import SwiftUI

/// Creates every service once and wires them together.
final class AppModel {
    let settings = AppSettings.shared
    let state: IslandState
    let media = MediaController()
    let notes = NotesStore()
    let clipboard = ClipboardManager()
    let shelf = ShelfStore()
    let keepAwake = KeepAwake()

    private var bag = Set<AnyCancellable>()

    init() {
        state = IslandState(settings: settings)
    }

    func start() {
        media.start()
        clipboard.limit = settings.clipboardLimit
        if settings.clipboardEnabled { clipboard.start() }

        // The compact island widens while music plays.
        media.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] live in self?.state.hasLiveActivity = live }
            .store(in: &bag)

        // Peek the new song when the track changes.
        media.$track
            .map { $0?.trackID }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.settings.showTrackToasts, !self.state.isExpanded,
                      self.media.isPlaying, let track = self.media.track else { return }
                let text = track.artist.isEmpty ? track.title : "\(track.title) · \(track.artist)"
                self.state.show(Toast(icon: "music.note", text: text))
            }
            .store(in: &bag)

        // Dragging a file onto the island opens the shelf.
        state.$isDropTargeted
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] targeted in
                guard let self, targeted else { return }
                self.state.expand(tab: .tools)
            }
            .store(in: &bag)

        settings.$clipboardEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.clipboard.start() } else { self?.clipboard.stop() }
            }
            .store(in: &bag)

        settings.$clipboardLimit
            .receive(on: RunLoop.main)
            .sink { [weak self] limit in self?.clipboard.limit = limit }
            .store(in: &bag)
    }
}
