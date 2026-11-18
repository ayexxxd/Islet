import AppKit
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case media, notes, tools, extras

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .media: return "music.note"
        case .notes: return "note.text"
        case .tools: return "square.grid.2x2.fill"
        case .extras: return "sparkles"
        }
    }
}

/// A short message that drops down below the notch for a couple of seconds.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var icon: String
    var text: String
}

/// Everything the island needs to know about its own shape and mode.
final class IslandState: ObservableObject {
    @Published var isExpanded = false
    @Published var tab: IslandTab
    @Published var isPinned = false
    @Published var isEditing = false
    @Published var isDropTargeted = false
    @Published var isHovering = false
    @Published var hasLiveActivity = false
    @Published var toast: Toast?
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasPhysicalNotch = false

    var onOpenSettings: (() -> Void)?

    /// Bumped to ask the notes tab to focus its editor.
    @Published var focusNotesRequest = 0

    static let sideSlot: CGFloat = 54
    static let toastHeight: CGFloat = 30

    let settings: AppSettings
    private var toastWork: DispatchWorkItem?

    init(settings: AppSettings) {
        self.settings = settings
        self.tab = settings.defaultTab
    }

    /// The hardware notch, widened or narrowed by the user's fine tuning.
    var notch: CGSize {
        CGSize(width: max(notchSize.width + CGFloat(settings.notchWidthOffset), 80), height: notchSize.height)
    }

    var headerHeight: CGFloat { max(notchSize.height, 32) }
    var contentHeight: CGFloat { CGFloat(settings.contentHeight) }

    /// The size of the black island right now, in points.
    var currentSize: CGSize {
        isExpanded ? expandedSize : compactSize
    }

    var expandedSize: CGSize {
        CGSize(width: CGFloat(settings.expandedWidth), height: headerHeight + contentHeight)
    }

    /// Size of the closed island, including any live activity or toast.
    var compactSize: CGSize {
        var size = notch
        if hasLiveActivity {
            size.width += Self.sideSlot * 2
        }
        if toast != nil {
            size.width = max(size.width, 300)
            size.height += Self.toastHeight
        }
        return size
    }

    /// The tab actually on screen. Falls back when the chosen tab was switched off.
    var visibleTab: IslandTab? {
        settings.isTabEnabled(tab) ? tab : settings.enabledTabs.first
    }

    func expand(tab newTab: IslandTab? = nil) {
        guard !isExpanded || newTab != nil else { return }
        let wasExpanded = isExpanded
        withAnimation(settings.animation) {
            if let newTab { tab = newTab }
            isExpanded = true
        }
        if !wasExpanded && settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(settings.animation) {
            isExpanded = false
            isPinned = false
            isEditing = false
        }
    }

    func select(_ newTab: IslandTab) {
        guard newTab != tab else { return }
        withAnimation(settings.animation) { tab = newTab }
        if settings.rememberLastTab { settings.defaultTab = newTab }
    }

    func show(_ newToast: Toast, duration: TimeInterval = 2.6) {
        toastWork?.cancel()
        withAnimation(settings.animation) { toast = newToast }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(self.settings.animation) { self.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
