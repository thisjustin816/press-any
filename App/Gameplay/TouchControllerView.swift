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
            safeBottom: Double(safeAreaInsets.bottom)
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
        context.setFillColor(UIColor.white.withAlphaComponent(0.13).cgColor)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(1.5)

        let layout = resolver.layout
        drawDPad(layout.dpad, in: context, active: lastInput.up || lastInput.down || lastInput.left || lastInput.right)
        drawControl(layout.b, in: context, label: "B", active: lastInput.b)
        drawControl(layout.a, in: context, label: "A", active: lastInput.a)
        drawControl(layout.select, in: context, label: "SELECT", active: lastInput.select)
        drawControl(layout.start, in: context, label: "START", active: lastInput.start)
        let actionLabels: [TouchAction: String] = [.menu: "MENU", .quickSave: "QUICK SAVE", .quickLoad: "QUICK LOAD"]
        for (action, rect) in layout.actions {
            guard let label = actionLabels[action] else { continue }
            drawControl(rect, in: context, label: label, active: false)
        }
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

    /// A cross, like the hardware's.
    private func drawDPad(_ touchRect: TouchRect, in context: CGContext, active: Bool) {
        let rect = CGRect(x: touchRect.x, y: touchRect.y, width: touchRect.width, height: touchRect.height)
        let arm = rect.width / 3
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0, dy: arm), cornerRadius: arm * 0.2)
        path.append(UIBezierPath(roundedRect: rect.insetBy(dx: arm, dy: 0), cornerRadius: arm * 0.2))
        path.usesEvenOddFillRule = false
        context.setFillColor(UIColor.white.withAlphaComponent(active ? 0.28 : 0.13).cgColor)
        context.addPath(path.cgPath)
        context.drawPath(using: .fill)
    }

    /// Square frames draw as circles, like A and B, and wide ones as pills, like START and SELECT.
    private func drawControl(_ touchRect: TouchRect, in context: CGContext, label: String, active: Bool) {
        let rect = CGRect(x: touchRect.x, y: touchRect.y, width: touchRect.width, height: touchRect.height)
        context.setFillColor(UIColor.white.withAlphaComponent(active ? 0.28 : 0.13).cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
        context.addPath(path.cgPath)
        context.drawPath(using: .fillStroke)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(10, min(rect.width, rect.height) * 0.24), weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.72),
        ]
        let string = NSAttributedString(string: label, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}
