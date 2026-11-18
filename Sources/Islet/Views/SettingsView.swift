import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var clipboard: ClipboardManager

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String? = nil

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Open when the pointer hovers the notch", isOn: $settings.openOnHover)
                if settings.openOnHover {
                    VStack(alignment: .leading, spacing: 2) {
                        Slider(value: $settings.hoverDelay, in: 0...0.8, step: 0.05) {
                            Text("Hover delay")
                        }
                        Text(String(format: "%.2f seconds before the island opens", settings.hoverDelay))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Click the notch to open the island.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $settings.closeDelay, in: 0.1...1.5, step: 0.05) {
                        Text("Close delay")
                    }
                    Text(String(format: "Stays open %.2f seconds after the pointer leaves", settings.closeDelay))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Toggle("Haptic feedback on open", isOn: $settings.hapticFeedback)
                if settings.enabledTabs.count > 1 {
                    Picker("Open on tab", selection: $settings.defaultTab) {
                        ForEach(settings.enabledTabs) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    Toggle("Reopen on the last tab I used", isOn: $settings.rememberLastTab)
                }
            }

            Section {
                Toggle("Media player", isOn: $settings.mediaEnabled)
                if settings.mediaEnabled {
                    Group {
                        Toggle("Shuffle and volume controls", isOn: $settings.playerExtrasEnabled)
                        Toggle("Animated audio bars", isOn: $settings.showVisualizer)
                        Toggle("Peek the song title when the track changes", isOn: $settings.showTrackToasts)
                    }
                    .padding(.leading, 16)
                }

                Toggle("Notes", isOn: $settings.notesEnabled)

                Toggle("Clipboard history", isOn: $settings.clipboardEnabled)
                if settings.clipboardEnabled {
                    Group {
                        Stepper(value: $settings.clipboardLimit, in: 5...30) {
                            Text("Remember \(settings.clipboardLimit) items")
                        }
                        Button("Clear history") { clipboard.clear() }
                        Text("History stays in memory only and is gone when Islet quits. Items flagged as secrets by password managers are skipped.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 16)
                }

                Toggle("File shelf", isOn: $settings.shelfEnabled)
                Toggle("Calendar", isOn: $settings.calendarEnabled)
                Toggle("Camera mirror", isOn: $settings.mirrorEnabled)
                Toggle("Quick actions", isOn: $settings.quickActionsEnabled)
                Toggle("Passwords shortcut", isOn: $settings.passwordsEnabled)
                if settings.passwordsEnabled {
                    Text("Adds a key button to the island header that opens Apple's Passwords app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 16)
                }
                Toggle("Keep awake button", isOn: $settings.keepAwakeEnabled)
                Toggle("Pin button", isOn: $settings.pinButtonEnabled)
            } header: {
                Text("Features")
            } footer: {
                Text("Anything switched off is removed from the island. A tab disappears once all of its features are off.")
            }

            Section("Size") {
                sizeSlider("Open width", value: $settings.expandedWidth, range: AppSettings.widthRange, step: 10)
                sizeSlider("Open height", value: $settings.contentHeight, range: AppSettings.heightRange, step: 2)
                sizeSlider("Notch outline width", value: $settings.notchWidthOffset, range: AppSettings.notchOffsetRange, step: 1, signed: true)
                Text("Use the outline slider if the black shape looks wider or narrower than your real notch. Changes apply live.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Reset size") { settings.resetLayout() }
            }

            Section("Shortcuts") {
                Toggle("Global keyboard shortcuts", isOn: $settings.hotKeysEnabled)
                if settings.hotKeysEnabled {
                    LabeledContent("Open or close the island", value: "⌃⌥Space")
                    if settings.notesEnabled {
                        LabeledContent("New quick note", value: "⌃⌥N")
                    }
                    if settings.passwordsEnabled {
                        LabeledContent("Open Passwords", value: "⌃⌥P")
                    }
                }
                LabeledContent("Close the island", value: "Esc")
            }

            Section("Appearance") {
                Picker("Animation", selection: $settings.animationStyle) {
                    ForEach(AnimationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Island material", selection: $settings.material) {
                    ForEach(IslandMaterial.allCases) { material in
                        Text(material.title).tag(material)
                    }
                }
                if settings.material == .glass {
                    Text("Liquid Glass needs macOS 26 or later. Older systems get a frosted blur instead.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Picker("Accent color", selection: $settings.accentChoice) {
                    // Matching the artwork only makes sense with the media player on.
                    ForEach(AccentChoice.allCases.filter { settings.mediaEnabled || $0 != .artwork }) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Toggle("Show over full screen apps", isOn: $settings.showInFullScreen)
                Button("Quit Islet") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: settings.enabledTabs)
        .frame(width: 480, height: 680)
    }

    private func sizeSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, signed: Bool = false) -> some View {
        HStack {
            Slider(value: value, in: range, step: step) {
                Text(title)
            }
            Text(String(format: signed ? "%+.0f" : "%.0f", value.wrappedValue))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = "Could not change the login item. Move Islet.app to Applications and try again."
        }
    }
}
