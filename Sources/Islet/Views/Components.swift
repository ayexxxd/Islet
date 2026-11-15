import AppKit
import SwiftUI

// MARK: - Notch shape

/// The island outline. Top corners flare outward into the menu bar,
/// bottom corners are rounded. Both radii animate.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(min(topRadius, rect.width / 4), 0)
        let bottom = max(min(bottomRadius, rect.height / 2, rect.width / 4), 0)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Transitions

/// Content fades, blurs and scales as the island morphs between modes.
struct BlurFade: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 6 : 0)
            .opacity(isActive ? 0 : 1)
            .scaleEffect(isActive ? 0.96 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .modifier(active: BlurFade(isActive: true), identity: BlurFade(isActive: false))
    }
}

// MARK: - Audio bars

/// Small animated equalizer. Purely decorative, it does not sample audio.
struct AudioBars: View {
    var isPlaying: Bool
    var color: Color
    var barCount = 5
    var maxHeight: CGFloat = 14

    private static let speeds: [Double] = [5.1, 7.3, 6.2, 8.4, 5.7, 6.9, 7.8]
    private static let phases: [Double] = [0.0, 1.7, 3.1, 0.9, 2.4, 4.0, 1.2]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: height(for: index, time: time))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func height(for index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return 3 }
        let speed = Self.speeds[index % Self.speeds.count]
        let phase = Self.phases[index % Self.phases.count]
        let fast = 0.5 + 0.5 * sin(time * speed + phase)
        let slow = 0.65 + 0.35 * sin(time * 1.3 + phase * 2)
        return 3 + (maxHeight - 3) * CGFloat(fast * slow)
    }
}

// MARK: - Scrub bar

/// Progress bar that can be dragged to seek.
struct ScrubBar: View {
    var progress: Double
    var tint: Color
    var onScrub: (Double) -> Void

    @State private var dragValue: Double? = nil
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let shown = min(max(dragValue ?? progress, 0), 1)
            let active = isHovering || dragValue != nil
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geometry.size.width * CGFloat(shown), 0))
                    .animation(dragValue == nil ? .linear(duration: 0.5) : nil, value: shown)
            }
            .frame(height: active ? 7 : 4)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(geometry.size.width, 1)
                        dragValue = Double(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { _ in
                        if let dragValue { onScrub(dragValue) }
                        dragValue = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 14)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Buttons and cards

/// Press feedback used by every island button.
struct IslandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Round icon button used in the header and in cards.
struct IconButton: View {
    var systemName: String
    var size: CGFloat = 12
    var isOn = false
    var tint: Color = .white
    var help: String = ""
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(isOn ? tint : Color.white.opacity(0.7))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(isOn ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .help(help)
    }
}

/// Rounded panel with a small caption, used in the tools tab.
struct Card<Content: View, Accessory: View>: View {
    var title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(Color.white.opacity(0.45))
                Spacer(minLength: 0)
                accessory()
            }
            .frame(height: 14)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - Island background

/// Behind-window blur used where Liquid Glass is not available.
struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Liquid Glass on macOS 26 and later, frosted blur before that.
struct GlassLayer: View {
    var shape: NotchShape

    @ViewBuilder var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: shape)
        } else {
            FrostedBackground()
        }
        #else
        FrostedBackground()
        #endif
    }
}

/// Solid black while closed so it blends with the notch. When open it turns
/// into glass, with a black fade at the top that melts into the hardware.
struct IslandBackground: View {
    var shape: NotchShape
    var useGlass: Bool
    var isExpanded: Bool
    var fadeHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if useGlass {
                if isExpanded {
                    GlassLayer(shape: shape)
                        .transition(.opacity)
                }
                Color.black
                    .opacity(isExpanded ? 0 : 1)
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.55), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
                .opacity(isExpanded ? 1 : 0)
            } else {
                Color.black
            }
        }
    }
}
