import EmulationCore
import GameplayInput
import UIKit

@MainActor
final class TouchControllerView: UIView {
    var onInputChanged: ((EmulatorInputState) -> Void)?
    /// A tap on the logo, or on the game picture when `pictureOpensMenu` is on. It never reaches the
    /// Game Boy's input.
    var onMenu: (() -> Void)?
    /// Called with every new layout, so the game picture can follow the layout's screen frame.
    var onLayoutChanged: ((TouchControlLayout) -> Void)?
    var hapticsEnabled = true
    var style: TouchControlStyle = .gameBoy {
        didSet { setNeedsLayout() }
    }
    var pictureOpensMenu = false {
        didSet { setNeedsLayout() }
    }
    var scaling: ScreenScaling = .integer {
        didSet { setNeedsLayout() }
    }
    var theme: ControllerTheme = .matchSystem {
        didSet { setNeedsDisplay() }
    }
    /// With a game controller connected only the body is drawn, and touches pass through.
    var showsControls = true {
        didSet {
            guard showsControls != oldValue else { return }
            isUserInteractionEnabled = showsControls
            if !showsControls { cancelInput() }
            setNeedsDisplay()
        }
    }
    var palette: ControllerPalette { .resolve(theme, for: traitCollection) }
    var layout: TouchControlLayout { resolver.layout }

    // Replaced with a layout for the real bounds in layoutSubviews, before any touch arrives.
    private var resolver = TouchInputResolver(layout: .make(.gameBoy, width: 0, height: 0))
    private var touchIDs: [ObjectIdentifier: Int] = [:]
    /// Where each touch on a menu area began. The menu opens when one lifts close by, so a thumb
    /// sliding across doesn't open it.
    private var menuTouches: [ObjectIdentifier: CGPoint] = [:]
    private var nextTouchID = 1
    private var lastInput = EmulatorInputState()
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        accessibilityIdentifier = "gameplay.touchControls"
        // The controls can't be played with VoiceOver, but its double-tap opens the menu, which the
        // corner buttons don't offer while the touch controls show.
        isAccessibilityElement = true
        accessibilityLabel = "Game"
        accessibilityHint = "Double-tap for the game menu."
        feedback.prepare()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TouchControllerView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
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
            displayScale: Double(traitCollection.displayScale),
            scaling: scaling,
            pictureOpensMenu: pictureOpensMenu
        ))
        touchIDs.removeAll()
        menuTouches.removeAll()
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
        let layout = resolver.layout
        let palette = self.palette
        drawBody(around: layout.screen, palette: palette, in: context)
        if let bezel = layout.bezel { drawBezel(bezel, around: layout.screen, palette: palette, in: context) }
        if let logo = layout.logo { drawLogo(in: cgRect(logo), palette: palette) }
        guard showsControls else { return }

        switch style {
        case .gameBoy:
            if let dpad = layout.drawnRect(.dpad) { drawCrossDPad(dpad, input: lastInput, palette: palette, in: context) }
            drawButtonGroove(palette: palette, in: context)
            drawRoundButton(.a, label: "A", active: lastInput.a, palette: palette, in: context)
            drawRoundButton(.b, label: "B", active: lastInput.b, palette: palette, in: context)
            drawTiltedPill(.select, label: "SELECT", active: lastInput.select, palette: palette, in: context)
            drawTiltedPill(.start, label: "START", active: lastInput.start, palette: palette, in: context)
        case .playtiles:
            if let guide = layout.alignmentGuide { drawAlignmentGuide(guide, palette: palette, in: context) }
            if let dpad = layout.drawnRect(.dpad) { drawCircleDPad(dpad, input: lastInput, palette: palette, in: context) }
            drawRoundButton(.a, label: nil, active: lastInput.a, palette: palette, in: context)
            drawRoundButton(.b, label: nil, active: lastInput.b, palette: palette, in: context)
            drawPill(layout.drawnRect(.select), label: "SELECT", active: lastInput.select, palette: palette, in: context)
            drawPill(layout.drawnRect(.start), label: "START", active: lastInput.start, palette: palette, in: context)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = point(for: touch)
            if resolver.layout.opensMenu(at: location) {
                menuTouches[ObjectIdentifier(touch)] = touch.location(in: self)
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
        let tappedMenu = touches.contains { touch in
            guard let start = menuTouches[ObjectIdentifier(touch)] else { return false }
            let end = touch.location(in: self)
            return hypot(end.x - start.x, end.y - start.y) <= 10 && resolver.layout.opensMenu(at: point(for: touch))
        }
        end(touches)
        if tappedMenu { onMenu?() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches)
    }

    override func accessibilityActivate() -> Bool {
        onMenu?()
        return true
    }

    func cancelInput() {
        resolver.cancelAllTouches()
        touchIDs.removeAll()
        menuTouches.removeAll()
        publish()
    }

    private func end(_ touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            menuTouches.removeValue(forKey: key)
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

    /// The controller's body, everywhere but the game picture, which shows through from below.
    private func drawBody(around screen: TouchRect, palette: ControllerPalette, in context: CGContext) {
        context.saveGState()
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(rect: cgRect(screen)))
        path.usesEvenOddFillRule = true
        path.addClip()
        fillVerticalGradient(bounds, from: palette.bodyTop, to: palette.bodyBottom, in: context)
        context.restoreGState()
    }

    /// The app's wordmark, printed at the bottom of the body.
    private func drawLogo(in rect: CGRect, palette: ControllerPalette) {
        let string = AppBrand.Wordmark.attributedString(size: 18, ink: palette.logo, accent: palette.logoAccent)
        let textSize = string.size()
        string.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }

    /// The glass around the game picture, rounded more at the bottom right, as on a Game Boy.
    private func drawBezel(_ bezelRect: TouchRect, around screen: TouchRect, palette: ControllerPalette, in context: CGContext) {
        let picture = cgRect(screen)
        let bezel = cgRect(bezelRect)
        let border = max(picture.minY - bezel.minY, 1)
        let path = roundedRect(bezel, radius: border * 0.8, bottomRightRadius: border * 3.5)
        path.append(UIBezierPath(rect: picture))
        path.usesEvenOddFillRule = true
        context.saveGState()
        path.addClip()
        fillVerticalGradient(bezel, from: palette.bezelTop, to: palette.bezelBottom, in: context)
        context.restoreGState()
    }

    /// Where the physical controller lines up: a band with a U-shaped tab, pressed into the body.
    private func drawAlignmentGuide(_ guide: TouchAlignmentGuide, palette: ControllerPalette, in context: CGContext) {
        let tab = cgRect(guide.tab)
        let path = UIBezierPath(rect: cgRect(guide.bar))
        path.append(UIBezierPath(
            roundedRect: tab,
            byRoundingCorners: [.bottomLeft, .bottomRight],
            cornerRadii: CGSize(width: tab.width / 2, height: tab.width / 2)
        ))
        context.setFillColor(palette.groove.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
    }

    /// A Game Boy's D-pad: a cross, each pressed arm darker.
    private func drawCrossDPad(_ touchRect: TouchRect, input: EmulatorInputState, palette: ControllerPalette, in context: CGContext) {
        let rect = cgRect(touchRect)
        let arm = rect.width / 3
        let corner = arm * 0.18
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0, dy: arm), cornerRadius: corner)
        path.append(UIBezierPath(roundedRect: rect.insetBy(dx: arm, dy: 0), cornerRadius: corner))
        context.setFillColor(palette.dpad.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()

        let arms: [(CGRect, Bool)] = [
            (CGRect(x: rect.minX + arm, y: rect.minY, width: arm, height: arm), input.up),
            (CGRect(x: rect.minX + arm, y: rect.maxY - arm, width: arm, height: arm), input.down),
            (CGRect(x: rect.minX, y: rect.minY + arm, width: arm, height: arm), input.left),
            (CGRect(x: rect.maxX - arm, y: rect.minY + arm, width: arm, height: arm), input.right),
        ]
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        context.setFillColor(palette.dpadPressed.cgColor)
        for (armRect, pressed) in arms where pressed { context.fill(armRect) }
        // The shallow dimple at the center.
        let dimple = arm * 0.55
        context.setFillColor(palette.dpadDimple.cgColor)
        context.fillEllipse(in: CGRect(x: rect.midX - dimple / 2, y: rect.midY - dimple / 2, width: dimple, height: dimple))
        context.restoreGState()
    }

    /// The Playtiles D-pad: four circles, each about a third of the pad across.
    private func drawCircleDPad(_ touchRect: TouchRect, input: EmulatorInputState, palette: ControllerPalette, in context: CGContext) {
        let rect = cgRect(touchRect)
        let diameter = rect.width * 121 / 347
        let centers: [(CGPoint, Bool)] = [
            (CGPoint(x: rect.midX, y: rect.minY + diameter / 2), input.up),
            (CGPoint(x: rect.midX, y: rect.maxY - diameter / 2), input.down),
            (CGPoint(x: rect.minX + diameter / 2, y: rect.midY), input.left),
            (CGPoint(x: rect.maxX - diameter / 2, y: rect.midY), input.right),
        ]
        for (center, pressed) in centers {
            context.setFillColor((pressed ? palette.dpadPressed : palette.dpad).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        }
    }

    /// The recessed channel A and B sit in, along the line between them.
    private func drawButtonGroove(palette: ControllerPalette, in context: CGContext) {
        guard let a = resolver.layout.drawnRect(.a), let b = resolver.layout.drawnRect(.b) else { return }
        let from = CGPoint(x: b.center.x, y: b.center.y)
        let to = CGPoint(x: a.center.x, y: a.center.y)
        let length = hypot(to.x - from.x, to.y - from.y)
        let height = CGFloat(a.width) + 10
        context.saveGState()
        context.translateBy(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        context.rotate(by: atan2(to.y - from.y, to.x - from.x))
        let groove = CGRect(x: -length / 2 - height / 2, y: -height / 2, width: length + height, height: height)
        context.setFillColor(palette.groove.cgColor)
        context.addPath(UIBezierPath(roundedRect: groove, cornerRadius: height / 2).cgPath)
        context.fillPath()
        context.restoreGState()
    }

    /// A or B: a domed button, lit from above. On a Game Boy the letter is printed below it.
    private func drawRoundButton(_ control: TouchControl, label: String?, active: Bool, palette: ControllerPalette, in context: CGContext) {
        guard let touchRect = resolver.layout.drawnRect(control) else { return }
        let rect = cgRect(touchRect)
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        if active {
            context.setFillColor(palette.buttonPressed.cgColor)
            context.fill(rect)
        } else {
            fillVerticalGradient(rect, from: palette.buttonTop, to: palette.buttonBottom, in: context)
        }
        context.restoreGState()
        guard let label else { return }
        drawLettering(label, size: 15, at: CGPoint(x: rect.midX, y: rect.midY), distance: rect.height / 2 + 5, tilt: buttonTilt, in: context, palette: palette)
    }

    /// START and SELECT on the Game Boy layout: a pill turned by the layout's tilt, its name
    /// printed level below it, as on a Game Boy.
    private func drawTiltedPill(_ control: TouchControl, label: String, active: Bool, palette: ControllerPalette, in context: CGContext) {
        guard let touchRect = resolver.layout.drawnRect(control) else { return }
        let rect = cgRect(touchRect)
        let tilt = CGFloat(resolver.layout.selectStartTilt)
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.rotate(by: tilt)
        let pill = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        context.setFillColor((active ? palette.pillPressed : palette.pill).cgColor)
        context.addPath(UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).cgPath)
        context.fillPath()
        context.restoreGState()
        // Just below the tilted pill's lowest point.
        let drop = abs(sin(tilt)) * rect.width / 2 + cos(tilt) * rect.height / 2
        drawLettering(label, size: 11, at: origin, distance: drop + 4, tilt: 0, in: context, palette: palette)
    }

    /// A flat pill with its label inside, as in the Playtiles artwork.
    private func drawPill(_ touchRect: TouchRect?, label: String, active: Bool, palette: ControllerPalette, in context: CGContext) {
        guard let touchRect else { return }
        let rect = cgRect(touchRect)
        context.setFillColor((active ? palette.pillPressed : palette.pill).cgColor)
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath)
        context.fillPath()
        let string = NSAttributedString(string: label, attributes: [
            .font: UIFont.systemFont(ofSize: max(9, rect.height * 0.36), weight: .bold),
            .kern: 1.0,
            .foregroundColor: palette.pillText,
        ])
        let size = string.size()
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    /// The Game Boy layout's printed lettering: small spaced capitals, `distance` below `origin`
    /// in a frame turned by `tilt`.
    private func drawLettering(_ label: String, size: CGFloat, at origin: CGPoint, distance: CGFloat, tilt: CGFloat, in context: CGContext, palette: ControllerPalette) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.rotate(by: tilt)
        let string = NSAttributedString(string: label, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .heavy),
            .kern: size * 0.12,
            .foregroundColor: palette.lettering,
        ])
        let textSize = string.size()
        // Kerning adds space after the last letter too; centering ignores it.
        string.draw(at: CGPoint(x: -(textSize.width - size * 0.12) / 2, y: distance))
        context.restoreGState()
    }

    /// The tilt of the line from B to A, which the channel and the A and B lettering follow.
    private var buttonTilt: CGFloat {
        let layout = resolver.layout
        return atan2(CGFloat(layout.a.center.y - layout.b.center.y), CGFloat(layout.a.center.x - layout.b.center.x))
    }

    private func fillVerticalGradient(_ rect: CGRect, from top: UIColor, to bottom: UIColor, in context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [top.cgColor, bottom.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, bottomRightRadius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRightRadius))
        path.addArc(withCenter: CGPoint(x: rect.maxX - bottomRightRadius, y: rect.maxY - bottomRightRadius), radius: bottomRightRadius, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.close()
        return path
    }

    private func cgRect(_ rect: TouchRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
