import AppKit
import SwiftUI

/// Extras tab with upcoming events, a camera mirror and quick actions.
struct ExtrasView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            if settings.calendarEnabled {
                CalendarCard()
            }
            if settings.mirrorEnabled {
                MirrorCard()
                    .frame(width: settings.calendarEnabled ? 150 : nil)
            }
            if settings.quickActionsEnabled {
                ActionsCard()
                    .frame(width: settings.calendarEnabled || settings.mirrorEnabled ? 136 : nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }
}

// MARK: - Calendar

struct CalendarCard: View {
    @EnvironmentObject var calendar: CalendarManager

    var body: some View {
        Card(title: "Up next") {
            EmptyView()
        } content: {
            switch calendar.access {
            case .unknown:
                VStack(spacing: 8) {
                    placeholder("calendar", "See today's and tomorrow's events here")
                    Button(action: { calendar.requestAccess() }) {
                        Text("Allow calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(IslandButtonStyle())
                }
            case .denied:
                placeholder("calendar.badge.exclamationmark", "Calendar access is off. Turn it on in System Settings, Privacy and Security.")
            case .granted:
                if calendar.events.isEmpty {
                    placeholder("checkmark.circle", "Nothing else today or tomorrow")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(calendar.events) { event in
                                row(event)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { calendar.refresh() }
    }

    private func row(_ event: CalendarManager.Item) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(timeText(event))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func timeText(_ event: CalendarManager.Item) -> String {
        let day = Calendar.current.isDateInToday(event.start) ? "Today" : "Tomorrow"
        if event.isAllDay { return "\(day), all day" }
        return "\(day), \(event.start.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Mirror

struct MirrorCard: View {
    @EnvironmentObject var camera: CameraManager

    var body: some View {
        Card(title: "Mirror") {
            if camera.isRunning {
                Button(action: { camera.stop() }) {
                    Text("Off")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .buttonStyle(IslandButtonStyle())
            }
        } content: {
            ZStack {
                if camera.isRunning {
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .transition(.opacity)
                } else if camera.isUnavailable {
                    placeholder("video.slash", "Camera access is off or no camera was found")
                } else {
                    Button(action: { camera.start() }) {
                        VStack(spacing: 6) {
                            Image(systemName: "person.crop.square")
                                .font(.system(size: 24))
                            Text("Tap to check yourself")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(IslandButtonStyle())
                }
            }
            .animation(.easeOut(duration: 0.25), value: camera.isRunning)
        }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Quick actions

struct ActionsCard: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Card(title: "Actions") {
            EmptyView()
        } content: {
            VStack(spacing: 5) {
                if settings.passwordsEnabled {
                    actionButton("key.fill", "Passwords") { QuickActions.openPasswords() }
                }
                actionButton("moon.fill", "Sleep display") { QuickActions.sleepDisplay() }
                actionButton("circle.lefthalf.filled", "Dark mode") { QuickActions.toggleDarkMode() }
                actionButton("tv", "Screen saver") { QuickActions.startScreenSaver() }
            }
        }
    }

    private func actionButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(Color.white.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
    }
}
