import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var island: IslandWindowController!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        model = AppModel()
        island = IslandWindowController(model: model)
        island.show()

        model.state.onOpenSettings = { [weak self] in self?.openSettings() }
        model.settings.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.setStatusItem(visible: visible) }
            .store(in: &bag)
        setStatusItem(visible: model.settings.showMenuBarIcon)

        let s = model.settings
        Publishers.CombineLatest3(s.$hotKeysEnabled, s.$notesEnabled, s.$passwordsEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Read after the change lands, so the newest values are used.
                DispatchQueue.main.async { self?.updateHotKeys() }
            }
            .store(in: &bag)

        model.start()
    }

    /// Registers only the shortcuts whose features are switched on.
    private func updateHotKeys() {
        let center = HotKeyCenter.shared
        let s = model.settings
        for id: UInt32 in [1, 2, 3] { center.unregister(id: id) }
        guard s.hotKeysEnabled else { return }

        // Control + Option + Space
        center.register(id: 1, keyCode: 49, modifiers: HotKeyCenter.controlOption) { [weak self] in
            self?.island.toggleFromKeyboard()
        }
        // Control + Option + N
        if s.notesEnabled {
            center.register(id: 2, keyCode: 45, modifiers: HotKeyCenter.controlOption) { [weak self] in
                self?.island.quickNote()
            }
        }
        // Control + Option + P
        if s.passwordsEnabled {
            center.register(id: 3, keyCode: 35, modifiers: HotKeyCenter.controlOption) { [weak self] in
                self?.model.state.collapse()
                QuickActions.openPasswords()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status item

    private func setStatusItem(visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Islet")

            let menu = NSMenu()
            menu.addItem(withTitle: "Open Island", action: #selector(toggleIsland), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Open Passwords", action: #selector(openPasswords), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Islet", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func toggleIsland() {
        model.state.isPinned = true
        model.state.expand()
    }

    @objc private func openPasswords() {
        QuickActions.openPasswords()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings window

    @objc func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(model.settings)
                .environmentObject(model.clipboard)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Islet Settings"
            window.contentView = NSHostingView(rootView: root)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        model.state.collapse()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Main menu (needed so copy and paste shortcuts work in notes)

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
