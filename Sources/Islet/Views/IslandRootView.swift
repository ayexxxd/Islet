import SwiftUI
import UniformTypeIdentifiers

/// The whole island. It is drawn at the top center of a larger transparent canvas.
struct IslandRootView: View {
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        let size = state.currentSize
        let isTall = size.height > state.notch.height + 1
        let isIdle = !state.isExpanded && !state.hasLiveActivity && state.toast == nil
        // No flare while idle, so the outline matches the hardware notch exactly.
        let topRadius: CGFloat = state.isExpanded ? 10 : (isIdle ? 0 : 4)
        let bottomRadius: CGFloat = state.isExpanded ? 30 : (isTall ? 18 : 10)
        let isPeeking = state.isHovering && !state.isExpanded

        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        let expanded = state.expandedSize
        let compact = state.compactSize

        // Each mode keeps its own fixed layout size, so nothing reflows while
        // the outline animates. The outline simply reveals or hides it.
        ZStack(alignment: .top) {
            if state.isExpanded {
                ExpandedView()
                    .frame(width: expanded.width, height: expanded.height, alignment: .top)
                    .transition(.islandContent)
            } else {
                CompactView()
                    .frame(width: compact.width, height: compact.height, alignment: .top)
                    .transition(.islandContent)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .padding(.horizontal, topRadius)
        .background(
            IslandBackground(
                shape: shape,
                useGlass: settings.material == .glass,
                isExpanded: state.isExpanded,
                fadeHeight: state.headerHeight * 1.7
            )
        )
        .clipShape(shape)
        .shadow(color: Color.black.opacity(state.isExpanded ? 0.35 : 0), radius: 20, x: 0, y: 10)
        .scaleEffect(isPeeking ? 1.03 : 1, anchor: .top)
        .onDrop(of: [UTType.fileURL], isTargeted: $state.isDropTargeted) { providers in
            shelf.handleDrop(providers)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(settings.animation, value: size)
        .animation(settings.animation, value: isPeeking)
        .animation(settings.animation, value: settings.material)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }
}

// MARK: - Compact

/// What you see while the island is closed. Artwork and bars hug the notch.
struct CompactView: View {
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var media: MediaController

    private var accent: Color { settings.accent(artworkTint: media.tint) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .frame(width: IslandState.sideSlot, height: state.notch.height)
                Spacer(minLength: 0)
                if !state.hasPhysicalNotch, state.hasLiveActivity {
                    centerLabel
                    Spacer(minLength: 0)
                }
                trailing
                    .frame(width: IslandState.sideSlot, height: state.notch.height)
            }
            .frame(height: state.notch.height)
            .opacity(state.hasLiveActivity ? 1 : 0)

            if let toast = state.toast {
                HStack(spacing: 6) {
                    Image(systemName: toast.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accent)
                    Text(toast.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: IslandState.toastHeight - 6)
                .padding(.bottom, 6)
                .id(toast.id)
                .transition(.islandContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { state.expand() }
    }

    @ViewBuilder private var leading: some View {
        if media.isPlaying {
            ArtworkView(image: media.artwork, cornerRadius: 5)
                .frame(width: 20, height: 20)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var trailing: some View {
        if media.isPlaying {
            if settings.showVisualizer {
                AudioBars(isPlaying: true, color: accent, barCount: 5, maxHeight: 14)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
            }
        } else {
            Color.clear
        }
    }

    private var centerLabel: some View {
        Text(media.track?.title ?? "")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color.white.opacity(0.85))
            .lineLimit(1)
            .frame(maxWidth: state.notch.width - 8)
    }
}

/// Album art with a music note fallback.
struct ArtworkView: View {
    var image: NSImage?
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                GeometryReader { geometry in
                    Image(systemName: "music.note")
                        .font(.system(size: geometry.size.width * 0.42, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Expanded

/// The open island with a header row beside the notch and a tab below it.
struct ExpandedView: View {
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var keepAwake: KeepAwake

    private var accent: Color { settings.accent(artworkTint: media.tint) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: state.headerHeight)
            ZStack {
                switch state.tab {
                case .media:
                    MediaView().transition(.islandContent)
                case .notes:
                    NotesView().transition(.islandContent)
                case .tools:
                    ToolsView().transition(.islandContent)
                }
            }
            .frame(height: state.contentHeight)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(IslandTab.allCases) { tab in
                    IconButton(
                        systemName: tab.icon,
                        size: 11,
                        isOn: state.tab == tab,
                        tint: accent,
                        help: tab.title
                    ) {
                        state.select(tab)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Keep the hardware notch area empty.
            Color.clear
                .frame(width: state.hasPhysicalNotch ? state.notch.width : 0)

            HStack(spacing: 6) {
                IconButton(
                    systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                    size: 10,
                    isOn: keepAwake.isOn,
                    tint: accent,
                    help: "Keep display awake"
                ) {
                    keepAwake.toggle()
                }
                IconButton(
                    systemName: state.isPinned ? "pin.fill" : "pin",
                    size: 10,
                    isOn: state.isPinned,
                    tint: accent,
                    help: "Keep island open"
                ) {
                    state.isPinned.toggle()
                }
                IconButton(systemName: "gearshape.fill", size: 11, help: "Settings") {
                    state.onOpenSettings?()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }
}
