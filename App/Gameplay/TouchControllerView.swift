import EmulationCore
import GameplayInput
import UIKit

@MainActor
final class TouchControllerView: UIView {
    var onInputChanged: ((EmulatorInputState) -> Void)?
    var hapticsEnabled = true

    // Replaced with a layout for the real bounds in layoutSubviews, before any touch arrives.
    private var resolver = TouchInputResolver(layout: TouchControllerView.layout(for: .zero))
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
        resolver = TouchInputResolver(layout: Self.layout(for: bounds))
        touchIDs.removeAll()
        lastInput = .init()
        onInputChanged?(lastInput)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.white.withAlphaComponent(0.13).cgColor)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(1.5)

        let layout = resolver.layout
        drawControl(layout.dpad, in: context, label: "+", active: lastInput.up || lastInput.down || lastInput.left || lastInput.right)
        drawControl(layout.b, in: context, label: "B", active: lastInput.b)
        drawControl(layout.a, in: context, label: "A", active: lastInput.a)
        drawControl(layout.select, in: context, label: "SELECT", active: lastInput.select)
        drawControl(layout.start, in: context, label: "START", active: lastInput.start)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = id(for: touch)
            resolver.touchBegan(id: id, point: point(for: touch))
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

    private func drawControl(_ touchRect: TouchRect, in context: CGContext, label: String, active: Bool) {
        let rect = CGRect(x: touchRect.x, y: touchRect.y, width: touchRect.width, height: touchRect.height)
        context.setFillColor(UIColor.white.withAlphaComponent(active ? 0.28 : 0.13).cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.28)
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

    private nonisolated static func layout(for bounds: CGRect) -> TouchControlLayout {
        let width = Double(bounds.width)
        let height = Double(bounds.height)
        let scale = max(0.75, min(width / 390.0, 1.35))
        let dpadSize = 126.0 * scale
        let button = 66.0 * scale
        let bottom = max(20.0, min(56.0, height * 0.055))
        let controlsY = height - bottom - dpadSize

        return TouchControlLayout(
            dpad: .init(x: 24 * scale, y: controlsY, width: dpadSize, height: dpadSize),
            a: .init(x: width - 24 * scale - button, y: controlsY + 8 * scale, width: button, height: button),
            b: .init(x: width - 42 * scale - button * 2, y: controlsY + 42 * scale, width: button, height: button),
            start: .init(x: width / 2 + 8 * scale, y: height - bottom - 26 * scale, width: 70 * scale, height: 24 * scale),
            select: .init(x: width / 2 - 78 * scale, y: height - bottom - 26 * scale, width: 70 * scale, height: 24 * scale)
        )
    }
}
