import AppKit
import Foundation

struct TransitionState: Decodable {
    let runId: String
    let mode: String
    let status: String
    let phase: String
    let step: Int?
    let startedAt: String
    let deadlineAt: String
}

final class BannerController: NSObject, NSApplicationDelegate {
    private let stateURL: URL
    private let cancelURL: URL
    private let expectedRunId: String
    private let panel: NSPanel
    private let accent = NSView()
    private let modeLabel = NSTextField(labelWithString: "SPACEWRIGHT")
    private let phaseLabel = NSTextField(labelWithString: "Preparing workspace transition")
    private let timeLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Stop", target: nil, action: nil)
    private var timer: Timer?
    private var terminalSince: Date?

    init(stateURL: URL, cancelURL: URL, expectedRunId: String) {
        self.stateURL = stateURL
        self.cancelURL = cancelURL
        self.expectedRunId = expectedRunId
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePanel()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        effect.layer?.masksToBounds = true
        panel.contentView?.addSubview(effect)

        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.wantsLayer = true
        accent.layer?.backgroundColor = NSColor(calibratedRed: 0.78, green: 1.0, blue: 0.20, alpha: 1).cgColor
        effect.addSubview(accent)

        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        modeLabel.textColor = NSColor(calibratedRed: 0.78, green: 1.0, blue: 0.20, alpha: 1)
        effect.addSubview(modeLabel)

        phaseLabel.translatesAutoresizingMaskIntoConstraints = false
        phaseLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        phaseLabel.textColor = .white
        phaseLabel.lineBreakMode = .byTruncatingTail
        effect.addSubview(phaseLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        effect.addSubview(timeLabel)

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        effect.addSubview(progress)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        effect.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            accent.topAnchor.constraint(equalTo: effect.topAnchor),
            accent.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            accent.widthAnchor.constraint(equalToConstant: 5),
            modeLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 24),
            modeLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 17),
            modeLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12),
            phaseLabel.leadingAnchor.constraint(equalTo: modeLabel.leadingAnchor),
            phaseLabel.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 6),
            phaseLabel.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -16),
            timeLabel.leadingAnchor.constraint(equalTo: modeLabel.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: phaseLabel.bottomAnchor, constant: 7),
            progress.leadingAnchor.constraint(equalTo: modeLabel.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -16),
            progress.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 7),
            progress.heightAnchor.constraint(equalToConstant: 3),
            cancelButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            cancelButton.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 72),
        ])

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 18))
        }
        panel.orderFrontRegardless()
    }

    @objc private func cancel() {
        try? Data(expectedRunId.utf8).write(to: cancelURL, options: .atomic)
        cancelButton.isEnabled = false
        cancelButton.title = "Stopping…"
    }

    private func refresh() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(TransitionState.self, from: data) else { return }
        if state.runId != expectedRunId {
            NSApp.terminate(nil)
            return
        }

        let title = state.mode.prefix(1).uppercased() + state.mode.dropFirst()
        modeLabel.stringValue = "SPACEWRIGHT  /  \(title)"
        phaseLabel.stringValue = state.phase

        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: state.startedAt) ?? Date()
        let deadline = formatter.date(from: state.deadlineAt) ?? Date()
        let now = Date()
        let total = max(1, deadline.timeIntervalSince(start))
        let elapsed = max(0, now.timeIntervalSince(start))
        let remaining = max(0, deadline.timeIntervalSince(now))
        progress.doubleValue = min(1, elapsed / total)
        timeLabel.stringValue = "Elapsed \(Int(elapsed))s  ·  safety stop in \(Int(ceil(remaining)))s" + (state.step.map { "  ·  step \($0)" } ?? "")

        if state.status != "running" {
            cancelButton.isHidden = true
            if terminalSince == nil { terminalSince = now }
            switch state.status {
            case "completed":
                accent.layer?.backgroundColor = NSColor.systemGreen.cgColor
                modeLabel.textColor = .systemGreen
            case "cancelled", "replaced":
                accent.layer?.backgroundColor = NSColor.systemOrange.cgColor
                modeLabel.textColor = .systemOrange
            default:
                accent.layer?.backgroundColor = NSColor.systemRed.cgColor
                modeLabel.textColor = .systemRed
            }
            timeLabel.stringValue = state.status.uppercased()
            progress.doubleValue = 1
            if now.timeIntervalSince(terminalSince!) > 1.8 { NSApp.terminate(nil) }
        }
    }
}

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: spacewright-banner STATUS_FILE CANCEL_FILE RUN_ID\n".utf8))
    exit(2)
}

let app = NSApplication.shared
let controller = BannerController(
    stateURL: URL(fileURLWithPath: CommandLine.arguments[1]),
    cancelURL: URL(fileURLWithPath: CommandLine.arguments[2]),
    expectedRunId: CommandLine.arguments[3]
)
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
