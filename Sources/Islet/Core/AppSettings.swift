import SwiftUI

enum AnimationStyle: String, CaseIterable, Identifiable {
    case bouncy, smooth, snappy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var animation: Animation {
        switch self {
        case .bouncy:
            return .spring(response: 0.46, dampingFraction: 0.74, blendDuration: 0.2)
        case .smooth:
            return .spring(response: 0.48, dampingFraction: 0.88, blendDuration: 0.2)
        case .snappy:
            return .spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.2)
        }
    }
}

enum IslandMaterial: String, CaseIterable, Identifiable {
    case glass, solid

    var id: String { rawValue }
    var title: String { self == .glass ? "Liquid Glass" : "Solid black" }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case artwork, white, blue, purple, pink, orange, green

    var id: String { rawValue }

    var title: String {
        self == .artwork ? "Match artwork" : rawValue.capitalized
    }

    var fixedColor: Color? {
        switch self {
        case .artwork: return nil
        case .white: return .white
        case .blue: return Color(red: 0.35, green: 0.68, blue: 1.0)
        case .purple: return Color(red: 0.72, green: 0.52, blue: 1.0)
        case .pink: return Color(red: 1.0, green: 0.45, blue: 0.68)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.25)
        case .green: return Color(red: 0.35, green: 0.9, blue: 0.55)
        }
    }
}

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: "openOnHover") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var hapticFeedback: Bool { didSet { defaults.set(hapticFeedback, forKey: "hapticFeedback") } }
    @Published var animationStyle: AnimationStyle { didSet { defaults.set(animationStyle.rawValue, forKey: "animationStyle") } }
    @Published var accentChoice: AccentChoice { didSet { defaults.set(accentChoice.rawValue, forKey: "accentChoice") } }
    @Published var showVisualizer: Bool { didSet { defaults.set(showVisualizer, forKey: "showVisualizer") } }
    @Published var showTrackToasts: Bool { didSet { defaults.set(showTrackToasts, forKey: "showTrackToasts") } }
    @Published var material: IslandMaterial { didSet { defaults.set(material.rawValue, forKey: "material") } }
    @Published var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: "clipboardEnabled") } }
    @Published var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: "clipboardLimit") } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var showInFullScreen: Bool { didSet { defaults.set(showInFullScreen, forKey: "showInFullScreen") } }
    @Published var defaultTab: IslandTab { didSet { defaults.set(defaultTab.rawValue, forKey: "defaultTab") } }
    @Published var rememberLastTab: Bool { didSet { defaults.set(rememberLastTab, forKey: "rememberLastTab") } }
    @Published var closeDelay: Double { didSet { defaults.set(closeDelay, forKey: "closeDelay") } }
    @Published var hotKeysEnabled: Bool { didSet { defaults.set(hotKeysEnabled, forKey: "hotKeysEnabled") } }

    // Layout
    @Published var expandedWidth: Double { didSet { defaults.set(expandedWidth, forKey: "expandedWidth") } }
    @Published var contentHeight: Double { didSet { defaults.set(contentHeight, forKey: "contentHeight") } }
    @Published var notchWidthOffset: Double { didSet { defaults.set(notchWidthOffset, forKey: "notchWidthOffset") } }

    static let widthRange: ClosedRange<Double> = 480...760
    static let heightRange: ClosedRange<Double> = 140...230
    static let notchOffsetRange: ClosedRange<Double> = -24...24

    private init() {
        let d = UserDefaults.standard
        openOnHover = d.object(forKey: "openOnHover") as? Bool ?? true
        hoverDelay = d.object(forKey: "hoverDelay") as? Double ?? 0.15
        hapticFeedback = d.object(forKey: "hapticFeedback") as? Bool ?? true
        animationStyle = AnimationStyle(rawValue: d.string(forKey: "animationStyle") ?? "") ?? .smooth
        accentChoice = AccentChoice(rawValue: d.string(forKey: "accentChoice") ?? "") ?? .artwork
        showVisualizer = d.object(forKey: "showVisualizer") as? Bool ?? true
        showTrackToasts = d.object(forKey: "showTrackToasts") as? Bool ?? true
        material = IslandMaterial(rawValue: d.string(forKey: "material") ?? "") ?? .glass
        clipboardEnabled = d.object(forKey: "clipboardEnabled") as? Bool ?? true
        clipboardLimit = d.object(forKey: "clipboardLimit") as? Int ?? 12
        showMenuBarIcon = d.object(forKey: "showMenuBarIcon") as? Bool ?? true
        showInFullScreen = d.object(forKey: "showInFullScreen") as? Bool ?? false
        defaultTab = IslandTab(rawValue: d.string(forKey: "defaultTab") ?? "") ?? .media
        rememberLastTab = d.object(forKey: "rememberLastTab") as? Bool ?? false
        closeDelay = d.object(forKey: "closeDelay") as? Double ?? 0.4
        hotKeysEnabled = d.object(forKey: "hotKeysEnabled") as? Bool ?? true
        expandedWidth = d.object(forKey: "expandedWidth") as? Double ?? 600
        contentHeight = d.object(forKey: "contentHeight") as? Double ?? 168
        notchWidthOffset = d.object(forKey: "notchWidthOffset") as? Double ?? 0
    }

    func resetLayout() {
        expandedWidth = 600
        contentHeight = 168
        notchWidthOffset = 0
    }

    var animation: Animation { animationStyle.animation }

    /// Accent used across the island. Falls back to the artwork tint.
    func accent(artworkTint: Color) -> Color {
        accentChoice.fixedColor ?? artworkTint
    }
}
