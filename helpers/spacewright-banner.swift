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
    private let lime = NSColor(calibratedRed: 0.78, green: 1.0, blue: 0.20, alpha: 1)
    private let ink = NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.055, alpha: 0.96)
    private let primaryText = NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.94, alpha: 1)
    private let secondaryText = NSColor(calibratedRed: 0.76, green: 0.81, blue: 0.85, alpha: 1)
    private let stopColor = NSColor(calibratedRed: 0.88, green: 0.25, blue: 0.16, alpha: 1)
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 124),
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
        panel.appearance = NSAppearance(named: .darkAqua)

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = lime.withAlphaComponent(0.34).cgColor
        effect.layer?.backgroundColor = ink.cgColor
        effect.layer?.masksToBounds = true
        panel.contentView?.addSubview(effect)

        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.wantsLayer = true
        accent.layer?.backgroundColor = lime.cgColor
        effect.addSubview(accent)

        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        modeLabel.textColor = lime
        effect.addSubview(modeLabel)

        phaseLabel.translatesAutoresizingMaskIntoConstraints = false
        phaseLabel.font = .systemFont(ofSize: 17, weight: .bold)
        phaseLabel.textColor = primaryText
        phaseLabel.lineBreakMode = .byTruncatingTail
        effect.addSubview(phaseLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        timeLabel.textColor = secondaryText
        effect.addSubview(timeLabel)

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.appearance = NSAppearance(named: .darkAqua)
        effect.addSubview(progress)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.isBordered = false
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 9
        cancelButton.layer?.backgroundColor = stopColor.cgColor
        cancelButton.font = .systemFont(ofSize: 13, weight: .bold)
        setCancelTitle("Stop")
        cancelButton.toolTip = "Stop this workspace transition"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        effect.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            accent.topAnchor.constraint(equalTo: effect.topAnchor),
            accent.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            accent.widthAnchor.constraint(equalToConstant: 5),
            modeLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 24),
            modeLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
            modeLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12),
            phaseLabel.leadingAnchor.constraint(equalTo: modeLabel.leadingAnchor),
            phaseLabel.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 6),
            phaseLabel.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -16),
            timeLabel.leadingAnchor.constraint(equalTo: modeLabel.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: phaseLabel.bottomAnchor, constant: 7),
            progress.leadingAnchor.constraint(equalTo: modeLabel.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -16),
            progress.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 7),
            progress.heightAnchor.constraint(equalToConstant: 4),
            cancelButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            cancelButton.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 82),
            cancelButton.heightAnchor.constraint(equalToConstant: 36),
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
        cancelButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.28, alpha: 1).cgColor
        setCancelTitle("Stopping…")
    }

    private func setCancelTitle(_ title: String) {
        cancelButton.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .bold)
            ]
        )
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
