import AppKit
import Combine
import SwiftUI

/// Borderless, transparent panel that sits above the menu bar.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Keep the window glued to the very top of the screen, over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view that reacts to the first click even when the panel is not key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    /// Size of the hardware notch, or nil when this display has none.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }
        let width = frame.width - left.width - right.width
        guard width > 0 else { return nil }
        return CGSize(width: width, height: safeAreaInsets.top)
    }

    var menuBarHeight: CGFloat {
        max(frame.maxY - visibleFrame.maxY, 24)
    }
}

/// Owns the panel, places it on the notch and turns raw mouse movement
/// into hover, expand and collapse decisions.
final class IslandWindowController {
    static let canvas = CGSize(width: 920, height: 440)

    private let model: AppModel
    private let panel: IslandPanel
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var safetyTimer: Timer?

    private var state: IslandState { model.state }
    private var settings: AppSettings { model.settings }

    init(model: AppModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))

        let root = IslandRootView()
            .environmentObject(model.state)
            .environmentObject(model.settings)
            .environmentObject(model.media)
            .environmentObject(model.notes)
            .environmentObject(model.clipboard)
            .environmentObject(model.shelf)
            .environmentObject(model.keepAwake)
            .environmentObject(model.calendar)
            .environmentObject(model.camera)
        let host = FirstMouseHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show() {
        applyCollectionBehavior()
        reposition()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &bag)

        settings.$showInFullScreen
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyCollectionBehavior() }
            .store(in: &bag)

        // The island can change size under a still cursor, so re-evaluate after any change.
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateMouse() }
            .store(in: &bag)

        state.$isExpanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                if !expanded { self?.releaseKeyboard() }
            }
            .store(in: &bag)
    }

    // MARK: - Placement

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.notchSize != nil }) ?? NSScreen.screens.first ?? NSScreen.main
    }

    private func reposition() {
        guard let screen = targetScreen() else { return }
        let frame = screen.frame
        let size = Self.canvas
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
        if let notch = screen.notchSize {
            state.hasPhysicalNotch = true
            state.notchSize = CGSize(width: notch.width, height: notch.height)
        } else {
            state.hasPhysicalNotch = false
            state.notchSize = CGSize(width: 190, height: screen.menuBarHeight)
        }
    }

    private func applyCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if settings.showInFullScreen { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
    }

    /// The island rectangle in screen coordinates.
    private func islandRect() -> NSRect {
        let frame = panel.frame
        let size = state.currentSize
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    // MARK: - Mouse handling

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            self?.evaluateMouse()
        }) { monitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            self?.evaluateMouse()
            return event
        }) { monitors.append(local) }

        // A click anywhere outside the island closes it.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, self.state.isExpanded, !self.state.isPinned else { return }
            self.state.collapse()
        }) { monitors.append(outside) }

        // Escape closes the island while it has the keyboard.
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, event.window === self.panel, self.state.isExpanded else { return event }
            self.state.collapse()
            return nil
        }) { monitors.append(keys) }

        // Safety net for moments when no mouse events arrive, such as file drags.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.evaluateMouse() }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }

    private func evaluateMouse() {
        let location = NSEvent.mouseLocation
        let inside = islandRect().insetBy(dx: -8, dy: -8).contains(location)

        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        guard inside != state.isHovering else { return }
        state.isHovering = inside

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            guard settings.openOnHover, !state.isExpanded else { return }
            scheduleExpand()
        } else {
            expandWork?.cancel()
            expandWork = nil
            scheduleCollapse()
        }
    }

    private func scheduleExpand() {
        expandWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.isHovering else { return }
            self.state.expand()
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.hoverDelay, execute: work)
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let s = self.state
            guard s.isExpanded, !s.isHovering, !s.isPinned, !s.isEditing, !s.isDropTargeted else { return }
            s.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.closeDelay, execute: work)
    }

    // MARK: - Global shortcuts

    /// Opens or closes the island from the keyboard.
    func toggleFromKeyboard() {
        if state.isExpanded {
            state.collapse()
        } else {
            state.isPinned = true
            state.expand()
        }
    }

    /// Opens the notes tab with a fresh note ready for typing.
    func quickNote() {
        model.notes.add()
        state.isPinned = true
        state.expand(tab: .notes)
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.state.focusNotesRequest += 1
        }
    }

    /// Hands keyboard focus back to whatever app the user was in.
    private func releaseKeyboard() {
        panel.makeFirstResponder(nil)
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}
