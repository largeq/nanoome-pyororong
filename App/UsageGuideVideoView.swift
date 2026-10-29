import AppKit
import AVKit

@MainActor
private final class GuidePlayerView: AVPlayerView {
    // AVKit still handles Space with hidden controls; the custom buttons own playback.
    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKeyView: Bool { false }
    override func becomeFirstResponder() -> Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class GuideVideoControlSurface: NSView {
    private let button: NSButton
    private let diameter: CGFloat
    private let opaqueOverlay = NSView()

    init(button: NSButton, diameter: CGFloat) {
        self.button = button
        self.diameter = diameter
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter)
        ])
        setAccessibilityElement(false)
        installMaterial()
        updateContrast()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateContrast()
    }

    @objc private func accessibilityOptionsChanged(_ notification: Notification) { updateContrast() }

    private func installMaterial() {
        let rect = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        let content = NSView(frame: rect)
        content.autoresizingMask = [.width, .height]
        opaqueOverlay.frame = rect
        opaqueOverlay.autoresizingMask = [.width, .height]
        opaqueOverlay.wantsLayer = true
        opaqueOverlay.layer?.backgroundColor = NSColor.black.cgColor
        opaqueOverlay.layer?.cornerRadius = diameter / 2
        content.addSubview(opaqueOverlay)
        button.frame = rect
        button.autoresizingMask = [.width, .height]
        content.addSubview(button)

        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: rect)
            glass.style = .clear
            glass.cornerRadius = diameter / 2
            glass.tintColor = NSColor.black.withAlphaComponent(0.18)
            glass.appearance = NSAppearance(named: .darkAqua)
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.contentView = content
            background = glass
        } else {
            let effect = NSVisualEffectView(frame: rect)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.appearance = NSAppearance(named: .darkAqua)
            effect.wantsLayer = true
            effect.layer?.cornerRadius = diameter / 2
            effect.layer?.masksToBounds = true
            effect.layer?.borderWidth = 1
            effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
            effect.addSubview(content)
            background = effect
        }
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        background.setAccessibilityElement(false)
        addSubview(background)
    }

    private func updateContrast() {
        let workspace = NSWorkspace.shared
        let highContrast = workspace.accessibilityDisplayShouldIncreaseContrast
            || [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua].contains(effectiveAppearance.name)
        opaqueOverlay.isHidden = !workspace.accessibilityDisplayShouldReduceTransparency && !highContrast
        opaqueOverlay.layer?.borderWidth = highContrast ? 2 : 1
        opaqueOverlay.layer?.borderColor = NSColor.white.withAlphaComponent(highContrast ? 0.95 : 0.4).cgColor
    }
}

@MainActor
final class UsageGuideVideoView: NSView {
    // Scene starts in the approved 12.93-second recording.
    static let stepTimes: [TimeInterval] = [0, 5, 9]

    var onStepChanged: ((Int) -> Void)?
    var onPlaybackRequested: ((Bool) -> Void)?
    let playerView: AVPlayerView = GuidePlayerView()
    let player: AVPlayer?
    let videoURL: URL?
    let backwardButton = GuideActionButton(title: "", target: nil, action: nil)
    let playbackButton = GuideActionButton(title: "", target: nil, action: nil)
    let forwardButton = GuideActionButton(title: "", target: nil, action: nil)
    private(set) var selectedStep = 0
    var isPlaying: Bool { (player?.rate ?? 0) > 0 }
    var playbackPosition: TimeInterval { player?.currentTime().seconds ?? 0 }
    private let controls = NSStackView()
    private var hoverTracking: NSTrackingArea?
    private var pointerIsInside = false
    private var controlsHaveFocus = false
    private var controlsAvailable = false
    private(set) var areControlsVisible = false
    private var requestedPlaying = false
    private var displayedPlaying: Bool?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var seekGeneration = 0
    private var pendingTarget: TimeInterval?
    private let unavailable = GuideText.label("사용법 영상을 불러오지 못했습니다. 왼쪽 설명을 따라 진행해 주세요.",
                                              size: 13, color: .secondaryLabelColor)

    private var duration: TimeInterval {
        let seconds = player?.currentItem?.duration.seconds ?? 0
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    init(frame: NSRect, bundle: Bundle = .main) {
        videoURL = bundle.url(forResource: "usage-guide", withExtension: "mp4")
        player = videoURL.map { AVPlayer(url: $0) }
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = false
        playerView.updatesNowPlayingInfoCenter = false
        if #available(macOS 13.0, *) { playerView.allowsVideoFrameAnalysis = false }
        playerView.setAccessibilityLabel("표 복사·변환·붙여넣기 시연 영상")
        player?.isMuted = true

        configure(backwardButton, symbol: "gobackward.5", label: "5초 뒤로", identifier: "guide-backward", size: 19)
        configure(playbackButton, symbol: "play.fill", label: "재생", identifier: "guide-playback", size: 25)
        configure(forwardButton, symbol: "goforward.5", label: "5초 앞으로", identifier: "guide-forward", size: 19)
        backwardButton.action = #selector(skipBackward)
        playbackButton.action = #selector(togglePlayback)
        forwardButton.action = #selector(skipForward)
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 16
        controls.alphaValue = 0
        for button in [backwardButton, playbackButton, forwardButton] {
            button.onFocusChanged = { [weak self] focused in
                self?.controlsHaveFocus = focused
                self?.updateControlsVisibility()
            }
        }
        controls.addArrangedSubview(GuideVideoControlSurface(button: backwardButton, diameter: 44))
        controls.addArrangedSubview(GuideVideoControlSurface(button: playbackButton, diameter: 64))
        controls.addArrangedSubview(GuideVideoControlSurface(button: forwardButton, diameter: 44))
        for view in [playerView, unavailable, controls] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: 800.0 / 1280.0),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            unavailable.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            unavailable.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            unavailable.centerYAnchor.constraint(equalTo: centerYAnchor),
            controls.centerXAnchor.constraint(equalTo: centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
            controls.widthAnchor.constraint(equalToConstant: 184),
            controls.heightAnchor.constraint(equalToConstant: 64)
        ])
        updateAvailability(failed: player == nil)
        if let player {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                                                         queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateState() }
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.playbackEnded() }
                }
            statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor [weak self] in self?.updateAvailability(failed: failed) }
            }
        }
        updateState()
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
        if let window {
            pointerIsInside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        updateControlsVisibility()
    }

    override func mouseEntered(with event: NSEvent) {
        pointerIsInside = true
        updateControlsVisibility(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        pointerIsInside = false
        updateControlsVisibility(animated: true)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return !areControlsVisible && hit.isDescendant(of: controls) ? self : hit
    }

    private func updateControlsVisibility(animated: Bool = false) {
        let visible = controlsAvailable && window?.isKeyWindow == true && (pointerIsInside || controlsHaveFocus)
        guard visible != areControlsVisible else { return }
        areControlsVisible = visible
        // Keep the controls in the key loop so Tab can reveal them without a mouse.
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                controls.animator().alphaValue = visible ? 1 : 0
            }
        } else {
            controls.alphaValue = visible ? 1 : 0
        }
    }

    isolated deinit {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    private func configure(_ button: NSButton, symbol: String, label: String, identifier: String, size: CGFloat) {
        button.target = self
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .circular
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        button.contentTintColor = .white
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    func setPlaying(_ playing: Bool) {
        requestedPlaying = playing && player != nil
        guard let player else { updateState(); return }
        if requestedPlaying {
            if pendingTarget == nil, duration > 0, playbackPosition >= duration - 0.05 {
                seek(to: 0)
            } else {
                player.play()
            }
        } else {
            player.pause()
        }
        updateState()
    }

    func selectStep(_ step: Int) {
        guard Self.stepTimes.indices.contains(step) else { return }
        selectedStep = step
        onStepChanged?(step)
        seek(to: Self.stepTimes[step])
    }

    func seek(by offset: TimeInterval) {
        guard offset.isFinite, duration > 0 else { return }
        seek(to: (pendingTarget ?? playbackPosition) + offset)
    }

    private func seek(to seconds: TimeInterval) {
        guard let player else { updateState(); return }
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        seekGeneration += 1
        let generation = seekGeneration
        pendingTarget = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekGeneration == generation else { return }
                self.pendingTarget = nil
                if self.requestedPlaying { self.player?.play() }
                else { self.player?.pause() }
                self.updateState()
            }
        }
        updateState()
    }

    @objc private func togglePlayback() {
        let playing = !requestedPlaying
        if let onPlaybackRequested { onPlaybackRequested(playing) }
        else { setPlaying(playing) }
    }

    @objc private func skipBackward() { seek(by: -5) }
    @objc private func skipForward() { seek(by: 5) }

    private func playbackEnded() {
        guard requestedPlaying, duration > 0, (pendingTarget ?? playbackPosition) >= duration - 0.05 else { return }
        seek(to: 0)
    }

    private func updateAvailability(failed: Bool) {
        controlsAvailable = !failed
        unavailable.isHidden = !failed
        playerView.isHidden = failed
        controls.isHidden = failed
        setAccessibilityChildren(failed ? [unavailable] : [playerView, backwardButton, playbackButton, forwardButton])
        updateState()
    }

    private func updateState() {
        if player != nil, pendingTarget == nil, playbackPosition.isFinite {
            let step = Self.stepTimes.lastIndex(where: { playbackPosition + 0.01 >= $0 }) ?? 0
            if selectedStep != step {
                selectedStep = step
                onStepChanged?(step)
            }
        }
        if displayedPlaying != requestedPlaying {
            displayedPlaying = requestedPlaying
            playbackButton.image = NSImage(systemSymbolName: requestedPlaying ? "pause.fill" : "play.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 25, weight: .semibold))
            let label = requestedPlaying ? "일시정지" : "재생"
            playbackButton.setAccessibilityLabel(label)
            playbackButton.toolTip = label
        }
        let available = player != nil && player?.currentItem?.status != .failed
        playbackButton.isEnabled = available
        backwardButton.isEnabled = available && duration > 0
        forwardButton.isEnabled = available && duration > 0
        updateControlsVisibility()
        let descriptions = ["한글에서 표를 포함한 내용을 복사합니다.",
                            "메뉴바에서 표 변환하기를 선택합니다.",
                            "변환 완료 후 네이버 카페·블로그 글쓰기에 붙여넣습니다(⌘V)."]
        setAccessibilityLabel("사용법 영상, \(selectedStep + 1)/3단계, \(requestedPlaying ? "재생 중" : "일시정지"). "
                              + descriptions[selectedStep])
    }
}
