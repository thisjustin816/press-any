import EmulationCore
import GameplayInput
import UIKit

@MainActor
final class TouchControllerView: UIView {
    var onInputChanged: ((EmulatorInputState) -> Void)?
    /// Taps on app controls such as Menu or Quick Save. They never reach the Game Boy's input.
    var onAction: ((TouchAction) -> Void)?
    /// Called with every new layout, so the game picture can follow the layout's screen frame.
    var onLayoutChanged: ((TouchControlLayout) -> Void)?
    var hapticsEnabled = true
    var style: TouchControlStyle = .gameBoy {
        didSet { setNeedsLayout() }
    }
    var layout: TouchControlLayout { resolver.layout }

    // Replaced with a layout for the real bounds in layoutSubviews, before any touch arrives.
    private var resolver = TouchInputResolver(layout: .make(.gameBoy, width: 0, height: 0))
    private var touchIDs: [ObjectIdentifier: Int] = [:]
    private var nextTouchID = 1
    private var lastInput = EmulatorInputState()
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        accessibilityIdentifier = "gameplay.touchControls"
        feedback.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolver = TouchInputResolver(layout: .make(
            style,
            width: Double(bounds.width),
            height: Double(bounds.height),
            safeTop: Double(safeAreaInsets.top),
            safeBottom: Double(safeAreaInsets.bottom),
            displayScale: Double(traitCollection.displayScale)
        ))
        touchIDs.removeAll()
        lastInput = .init()
        onInputChanged?(lastInput)
        onLayoutChanged?(resolver.layout)
        setNeedsDisplay()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(1.5)

        let layout = resolver.layout
        let dpadActive = lastInput.up || lastInput.down || lastInput.left || lastInput.right
        switch style {
        case .gameBoy:
            if let dpad = layout.drawnRect(.dpad) { drawCrossDPad(dpad, in: context, active: dpadActive) }
            drawRoundButton(.a, label: "A", active: lastInput.a, in: context)
            drawRoundButton(.b, label: "B", active: lastInput.b, in: context)
            drawTiltedPill(at: layout.select.center, label: "SELECT", active: lastInput.select, in: context)
            drawTiltedPill(at: layout.start.center, label: "START", active: lastInput.start, in: context)
        case .playtiles:
            if let dpad = layout.drawnRect(.dpad) { drawCircleDPad(dpad, in: context, input: lastInput) }
            drawRoundButton(.a, label: nil, active: lastInput.a, in: context)
            drawRoundButton(.b, label: nil, active: lastInput.b, in: context)
            drawPill(layout.drawnRect(.select), label: "SELECT", active: lastInput.select, in: context)
            drawPill(layout.drawnRect(.start), label: "START", active: lastInput.start, in: context)
        }
        drawPill(layout.drawnRect(.action(.menu)), label: "MENU", active: false, in: context)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = point(for: touch)
            if let action = resolver.layout.action(at: location) {
                onAction?(action)
                continue
            }
            resolver.touchBegan(id: id(for: touch), point: location)
        }
        publish()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let id = touchIDs[ObjectIdentifier(touch)] else { continue }
            resolver.touchMoved(id: id, point: point(for: touch))
        }
        publish()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches)
    }

    func cancelInput() {
        resolver.cancelAllTouches()
        touchIDs.removeAll()
        publish()
    }

    private func end(_ touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let id = touchIDs.removeValue(forKey: key) else { continue }
            resolver.touchEnded(id: id)
        }
        publish()
    }

    private func id(for touch: UITouch) -> Int {
        let key = ObjectIdentifier(touch)
        if let existing = touchIDs[key] { return existing }
        let id = nextTouchID
        nextTouchID += 1
        touchIDs[key] = id
        return id
    }

    private func point(for touch: UITouch) -> TouchPoint {
        let location = touch.location(in: self)
        return TouchPoint(x: location.x, y: location.y)
    }

    private func publish() {
        let next = resolver.input
        if hapticsEnabled, hasNewPress(previous: lastInput, next: next) {
            feedback.impactOccurred(intensity: 0.55)
            feedback.prepare()
        }
        lastInput = next
        onInputChanged?(next)
        setNeedsDisplay()
    }

    private func hasNewPress(previous: EmulatorInputState, next: EmulatorInputState) -> Bool {
        (!previous.up && next.up) || (!previous.down && next.down)
            || (!previous.left && next.left) || (!previous.right && next.right)
            || (!previous.a && next.a) || (!previous.b && next.b)
            || (!previous.start && next.start) || (!previous.select && next.select)
    }

    private func fill(_ active: Bool) -> CGColor {
        UIColor.white.withAlphaComponent(active ? 0.30 : 0.14).cgColor
    }

    /// SameBoy's D-pad: a cross.
    private func drawCrossDPad(_ touchRect: TouchRect, in context: CGContext, active: Bool) {
        let rect = cgRect(touchRect)
        let arm = rect.width / 3
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0, dy: arm), cornerRadius: arm * 0.2)
        path.append(UIBezierPath(roundedRect: rect.insetBy(dx: arm, dy: 0), cornerRadius: arm * 0.2))
        context.setFillColor(fill(active))
        context.addPath(path.cgPath)
        context.drawPath(using: .fill)
    }

    /// The Playtiles D-pad: four circles, each about a third of the pad across.
    private func drawCircleDPad(_ touchRect: TouchRect, in context: CGContext, input: EmulatorInputState) {
        let rect = cgRect(touchRect)
        let diameter = rect.width * 121 / 347
        let centers: [(CGPoint, Bool)] = [
            (CGPoint(x: rect.midX, y: rect.minY + diameter / 2), input.up),
            (CGPoint(x: rect.midX, y: rect.maxY - diameter / 2), input.down),
            (CGPoint(x: rect.minX + diameter / 2, y: rect.midY), input.left),
            (CGPoint(x: rect.maxX - diameter / 2, y: rect.midY), input.right),
        ]
        for (center, active) in centers {
            context.setFillColor(fill(active))
            context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        }
    }

    /// A and B as circles at their drawn size, labeled below and to the right as SameBoy does.
    private func drawRoundButton(_ control: TouchControl, label: String?, active: Bool, in context: CGContext) {
        guard let touchRect = resolver.layout.drawnRect(control) else { return }
        let rect = cgRect(touchRect)
        context.setFillColor(fill(active))
        context.fillEllipse(in: rect)
        guard let label else { return }
        // SameBoy's label size and distance from the button's center.
        drawRotatedLabel(label, size: 24, at: CGPoint(x: rect.midX, y: rect.midY), distance: 40, in: context)
    }

    /// SameBoy's START and SELECT: a short pill tilted 30 degrees, labeled underneath.
    private func drawTiltedPill(at center: TouchPoint, label: String, active: Bool, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -.pi / 6)
        let pill = CGRect(x: -30, y: -7, width: 60, height: 14)
        context.setFillColor(fill(active))
        context.addPath(UIBezierPath(roundedRect: pill, cornerRadius: 7).cgPath)
        context.fillPath()
        context.restoreGState()
        drawRotatedLabel(label, size: 20, at: CGPoint(x: center.x, y: center.y), distance: 24, in: context)
    }

    /// A flat pill with its label inside, as in the Playtiles artwork.
    private func drawPill(_ touchRect: TouchRect?, label: String, active: Bool, in context: CGContext) {
        guard let touchRect else { return }
        let rect = cgRect(touchRect)
        context.setFillColor(fill(active))
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath)
        context.fillPath()
        let string = NSAttributedString(string: label, attributes: [
            .font: UIFont.systemFont(ofSize: max(9, rect.height * 0.42), weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8),
        ])
        let size = string.size()
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    /// Text rotated with SameBoy's -30 degree tilt, `distance` below `origin` in the tilted frame.
    private func drawRotatedLabel(_ label: String, size: CGFloat, at origin: CGPoint, distance: CGFloat, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.rotate(by: -.pi / 6)
        let string = NSAttributedString(string: label, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.6),
        ])
        let textSize = string.size()
        string.draw(at: CGPoint(x: -textSize.width / 2, y: distance))
        context.restoreGState()
    }

    private func cgRect(_ rect: TouchRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
