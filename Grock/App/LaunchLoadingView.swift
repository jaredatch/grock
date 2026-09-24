import AppKit
import QuartzCore

/// Face-on planet, one rail, one bead. Cold-launch cover (DEC-042).
enum LaunchLoadingLayout {
    static let canvas: CGFloat = 135
    static let planetRadius: CGFloat = 24
    static let orbitRadius: CGFloat = 39
    static let beadRadius: CGFloat = 7
    static let railStroke: CGFloat = 1.8
    /// 1.5s / 1.15 ≈ 1.3s.
    static let period: TimeInterval = 1.3
    static let pulsePeriod: TimeInterval = 1.15
    static let pulseAmount: CGFloat = 0.035
    /// Below window center so it sits in the content, not the titlebar.
    static let centerYOffset: CGFloat = -(PanelGeometry.fallbackTitlebarInset / 2 + 16)
    static let hideDuration: TimeInterval = 0.18
    static let revealDuration: TimeInterval = 0.26

    static func angle(period: TimeInterval, at time: TimeInterval, phase: CGFloat = 0) -> CGFloat {
        guard period > 0 else { return phase }
        return phase + CGFloat(time.truncatingRemainder(dividingBy: period) / period) * 2 * .pi
    }

    /// Clockwise from the top, matching the simple loop we are drawing.
    static func beadCenter(at time: TimeInterval) -> CGPoint {
        let a = CGFloat.pi / 2 - angle(period: period, at: time)
        return CGPoint(x: orbitRadius * cos(a), y: orbitRadius * sin(a))
    }
}

/// Drawn on the panel host while the WebView is covered. Ink follows appearance.
final class LaunchLoadingView: NSView {
    private var frameLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var time: TimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func start() {
        guard frameLink == nil else { return }
        lastTimestamp = 0
        let link = displayLink(target: self, selector: #selector(stepAnimation(_:)))
        link.add(to: .main, forMode: .common)
        frameLink = link
        needsDisplay = true
    }

    func stop() {
        frameLink?.invalidate()
        frameLink = nil
        lastTimestamp = 0
    }

    deinit {
        frameLink?.invalidate()
    }

    @objc private func stepAnimation(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastTimestamp > 0 {
            time += now - lastTimestamp
        }
        lastTimestamp = now
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY)

        let color = inkColor()
        color.setFill()
        color.setStroke()

        let pulse = 1 + LaunchLoadingLayout.pulseAmount * sin(
            LaunchLoadingLayout.angle(period: LaunchLoadingLayout.pulsePeriod, at: time)
        )
        let planetR = LaunchLoadingLayout.planetRadius * pulse
        NSBezierPath(ovalIn: NSRect(x: -planetR, y: -planetR, width: planetR * 2, height: planetR * 2)).fill()

        let orbitR = LaunchLoadingLayout.orbitRadius
        let rail = NSBezierPath(ovalIn: NSRect(x: -orbitR, y: -orbitR, width: orbitR * 2, height: orbitR * 2))
        rail.lineWidth = LaunchLoadingLayout.railStroke
        rail.stroke()

        let bead = LaunchLoadingLayout.beadCenter(at: time)
        let beadR = LaunchLoadingLayout.beadRadius
        NSBezierPath(ovalIn: NSRect(
            x: bead.x - beadR,
            y: bead.y - beadR,
            width: beadR * 2,
            height: beadR * 2
        )).fill()

        ctx.restoreGState()
    }

    private func inkColor() -> NSColor {
        let appearance = effectiveAppearance
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? .white : .black
    }
}
