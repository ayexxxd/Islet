import AVFoundation
import AppKit
import EventKit
import SwiftUI

// MARK: - Calendar

/// Upcoming events for today and tomorrow, read through EventKit.
final class CalendarManager: ObservableObject {
    enum Access {
        case unknown, granted, denied
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
        let color: Color
    }

    @Published private(set) var events: [Item] = []
    @Published private(set) var access: Access = .unknown

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Reloads events if access was already given. Never shows a prompt.
    func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        var allowed = false
        if #available(macOS 14.0, *) {
            allowed = status == .fullAccess
        } else {
            allowed = status == .authorized
        }

        if allowed {
            access = .granted
            load()
        } else if status == .notDetermined {
            access = .unknown
        } else {
            access = .denied
        }
    }

    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async { self?.finishRequest(granted) }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async { self?.finishRequest(granted) }
            }
        }
    }

    private func finishRequest(_ granted: Bool) {
        access = granted ? .granted : .denied
        if granted { load() }
    }

    private func load() {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .sorted(by: { $0.startDate < $1.startDate })
            .prefix(8)

        events = found.map { event in
            Item(
                id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "Untitled",
                start: event.startDate,
                isAllDay: event.isAllDay,
                color: Color(nsColor: event.calendar.color)
            )
        }
    }
}

// MARK: - Camera mirror

/// Runs the camera only while the mirror card is switched on.
final class CameraManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isUnavailable = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "islet.camera")
    private var isConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.run() } else { self?.isUnavailable = true }
                }
            }
        default:
            isUnavailable = true
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func run() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.isUnavailable = true }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .medium
                self.session.addInput(input)
                self.session.commitConfiguration()
                self.isConfigured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                self.isUnavailable = false
                self.isRunning = true
            }
        }
    }
}

/// AppKit view hosting the live preview, flipped like a mirror.
final class CameraPreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.setAffineTransform(.identity)
        previewLayer.frame = bounds
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        CATransaction.commit()
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        CameraPreviewView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}
}

// MARK: - Quick actions

enum QuickActions {
    /// Opens Apple's Passwords app, or the Passwords pane in System Settings
    /// on macOS versions that do not have the app.
    static func openPasswords() {
        let workspace = NSWorkspace.shared
        if let app = workspace.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
            workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else if let pane = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
            workspace.open(pane)
        }
    }

    static func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    static func startScreenSaver() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// Flips light and dark appearance. macOS asks once to let Islet control System Events.
    static func toggleDarkMode() {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }
}
