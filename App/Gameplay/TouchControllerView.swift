import EmulationCore
import EmulatorDomain
import GameplayInput
import UIKit

@MainActor
final class TouchControllerView: UIView {
    var onInputChanged: ((EmulatorInputState) -> Void)?
    /// Called with every new layout, so the game picture can follow the layout's screen frame.
    var onLayoutChanged: ((TouchControlLayout) -> Void)?
    /// How hard a new press taps back, or nil for no haptics.
    var hapticIntensity: CGFloat? = 0.55
    var style: TouchControlStyle = .gameBoy {
        didSet { setNeedsLayout() }
    }
    /// Adds the game picture to the layout's menu areas, which the gameplay screen covers with its
    /// menu buttons.
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
    private var palette: ControllerPalette { .resolve(theme, for: traitCollection) }
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
            resolver.touchBegan(id: id(for: touch), point: point(for: touch))
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
        if let hapticIntensity, hasNewPress(previous: lastInput, next: next) {
            feedback.impactOccurred(intensity: hapticIntensity)
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

    /// The glass around the game picture, rounded more at the bottom right, as on a Game Boy. That
    /// corner's arc passes the picture's corner at half the border's width: with radius r and border
    /// b the gap is r - √2 (r - b), so r = (√2 - 1/2) b / (√2 - 1), about 2.2 b.
    private func drawBezel(_ bezelRect: TouchRect, around screen: TouchRect, palette: ControllerPalette, in context: CGContext) {
        let picture = cgRect(screen)
        let bezel = cgRect(bezelRect)
        // Playtiles under Fill scaling fills its whole frame, leaving no border to draw.
        let border = picture.minY - bezel.minY
        guard border >= 1 else { return }
        let bottomRightRadius = (2.0.squareRoot() - 0.5) * border / (2.0.squareRoot() - 1)
        let path = roundedRect(bezel, radius: border * 0.8, bottomRightRadius: bottomRightRadius)
        path.append(UIBezierPath(rect: picture))
        path.usesEvenOddFillRule = true
        context.saveGState()
        path.addClip()
        fillVerticalGradient(bezel, from: palette.bezelTop, to: palette.bezelBottom, in: context)
        context.restoreGState()
    }

    /// Where the physical controller lines up: a band with a U-shaped tab, raised from the body as a
    /// ledge the controller fits against. Lit from above, its top edge catches the light and it
    /// casts a shadow below.
    private func drawAlignmentGuide(_ guide: TouchAlignmentGuide, palette: ControllerPalette, in context: CGContext) {
        let tab = cgRect(guide.tab)
        let path = UIBezierPath(rect: cgRect(guide.bar))
        path.append(UIBezierPath(
            roundedRect: tab,
            byRoundingCorners: [.bottomLeft, .bottomRight],
            cornerRadii: CGSize(width: tab.width / 2, height: tab.width / 2)
        ))
        func fill(_ color: UIColor, offsetBy dy: CGFloat) {
            context.saveGState()
            context.translateBy(x: 0, y: dy)
            context.setFillColor(color.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
            context.restoreGState()
        }
        fill(palette.guideShadow, offsetBy: 1.5)
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        fill(palette.guideHighlight, offsetBy: 0)
        fill(palette.guide, offsetBy: 1)
        context.restoreGState()
    }

    /// A Game Boy's D-pad: one raised cross with an arrow pressed into each arm and a shallow dip
    /// at the center. The pad doesn't sink when pressed; it tips, so the pressed arm's end goes into
    /// shade that fades out toward the center, with no edge between pressed and unpressed.
    private func drawCrossDPad(_ touchRect: TouchRect, input: EmulatorInputState, palette: ControllerPalette, in context: CGContext) {
        let rect = cgRect(touchRect)
        let arm = rect.width / 3
        let corner = arm * 0.18
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // One outline, so the rim follows the cross's edge and not the two bars inside it.
        let path = UIBezierPath(cgPath: UIBezierPath(roundedRect: rect.insetBy(dx: 0, dy: arm), cornerRadius: corner).cgPath
            .union(UIBezierPath(roundedRect: rect.insetBy(dx: arm, dy: 0), cornerRadius: corner).cgPath))
        drawRaised(path, top: lighter(palette.dpad), bottom: palette.dpad, pressedFace: palette.dpad, pressed: false, palette: palette, in: context)

        // Each arm's outer end, and the angle its arrow points.
        let sides: [(end: CGPoint, angle: CGFloat, pressed: Bool)] = [
            (CGPoint(x: rect.midX, y: rect.minY), -.pi / 2, input.up),
            (CGPoint(x: rect.midX, y: rect.maxY), .pi / 2, input.down),
            (CGPoint(x: rect.minX, y: rect.midY), .pi, input.left),
            (CGPoint(x: rect.maxX, y: rect.midY), 0, input.right),
        ]
        // Each arrow sits in the middle of its arm, two thirds of the way out from the center.
        for side in sides {
            let point = CGPoint(x: (side.end.x * 2 + center.x) / 3, y: (side.end.y * 2 + center.y) / 3)
            drawArrow(pointing: side.angle, at: point, size: rect.width / 7, palette: palette, in: context)
        }

        let dimple = arm * 0.62
        let dip = UIBezierPath(ovalIn: CGRect(x: center.x - dimple / 2, y: center.y - dimple / 2, width: dimple, height: dimple))
        context.setFillColor(palette.dpadDimple.cgColor)
        context.addPath(dip.cgPath)
        context.fillPath()
        // Hollowed out, so lit the other way round: shade under its top edge, light along its bottom.
        drawEdges(dip, top: palette.edgeShade, bottom: palette.edgeLight, in: context)

        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        for side in sides where side.pressed {
            guard let tip = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [palette.dpadTilt.cgColor, palette.dpadTilt.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            ) else { continue }
            context.drawLinearGradient(tip, start: side.end, end: center, options: [])
        }
        context.restoreGState()
    }

    /// An arrow pressed into a D-pad arm, pointing outward. Like the menu button's wordmark, lit from
    /// above: its floor is in shade and light catches the edge below it.
    private func drawArrow(pointing angle: CGFloat, at point: CGPoint, size: CGFloat, palette: ControllerPalette, in context: CGContext) {
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: size / 2, y: 0))
        triangle.addLine(to: CGPoint(x: -size / 2, y: -size * 0.55))
        triangle.addLine(to: CGPoint(x: -size / 2, y: size * 0.55))
        triangle.close()
        triangle.apply(CGAffineTransform(rotationAngle: angle))
        triangle.apply(CGAffineTransform(translationX: point.x, y: point.y))
        context.saveGState()
        context.translateBy(x: 0, y: 1)
        context.setFillColor(palette.edgeLight.cgColor)
        context.addPath(triangle.cgPath)
        context.fillPath()
        context.restoreGState()
        context.setFillColor(palette.dpadDimple.cgColor)
        context.addPath(triangle.cgPath)
        context.fillPath()
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
            let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                .offsetBy(dx: 0, dy: pressed ? Self.pressDepth : 0)
            drawRaised(UIBezierPath(ovalIn: circle), top: lighter(palette.dpad), bottom: palette.dpad, pressedFace: palette.dpadPressed, pressed: pressed, palette: palette, in: context)
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
        let face = rect.offsetBy(dx: 0, dy: active ? Self.pressDepth : 0)
        drawRaised(UIBezierPath(ovalIn: face), top: palette.buttonTop, bottom: palette.buttonBottom, pressedFace: palette.buttonPressed, pressed: active, palette: palette, in: context)
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
            .offsetBy(dx: 0, dy: active ? Self.pressDepth : 0)
        drawRaised(UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2), top: lighter(palette.pill), bottom: palette.pill, pressedFace: palette.pillPressed, pressed: active, palette: palette, in: context)
        context.restoreGState()
        // Just below the tilted pill's lowest point.
        let drop = abs(sin(tilt)) * rect.width / 2 + cos(tilt) * rect.height / 2
        drawLettering(label, size: 11, at: origin, distance: drop + 4, tilt: 0, in: context, palette: palette)
    }

    /// A pill with its label inside, as in the Playtiles artwork.
    private func drawPill(_ touchRect: TouchRect?, label: String, active: Bool, palette: ControllerPalette, in context: CGContext) {
        guard let touchRect else { return }
        let rect = cgRect(touchRect).offsetBy(dx: 0, dy: active ? Self.pressDepth : 0)
        drawRaised(UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2), top: lighter(palette.pill), bottom: palette.pill, pressedFace: palette.pillPressed, pressed: active, palette: palette, in: context)
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

    /// How far a pressed control's face sinks, as the menu button's wordmark does.
    private static let pressDepth: CGFloat = 1

    /// A control raised from the body like the menu button: a face lit from above, with light along
    /// its top edge and shade along its bottom, a thin rim, and a shadow below. Pressed, the face goes flat and the shadow shrinks; callers move the path
    /// down by `pressDepth` so it sinks too.
    private func drawRaised(
        _ path: UIBezierPath,
        top: UIColor,
        bottom: UIColor,
        pressedFace: UIColor,
        pressed: Bool,
        palette: ControllerPalette,
        in context: CGContext
    ) {
        context.saveGState()
        // A shadow offset is in device space, so it falls straight down even on a tilted pill.
        context.setShadow(
            offset: CGSize(width: 0, height: pressed ? 1 : 3),
            blur: 4,
            color: UIColor.black.withAlphaComponent(pressed ? 0.15 : 0.4).cgColor
        )
        context.setFillColor((pressed ? pressedFace : bottom).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.restoreGState()
        if !pressed {
            context.saveGState()
            context.addPath(path.cgPath)
            context.clip()
            fillVerticalGradient(path.bounds, from: top, to: bottom, in: context)
            context.restoreGState()
        }
        // Raised, light catches the top edge and the bottom edge is in shade. Pressed in, the top
        // edge shades the face instead.
        if pressed {
            drawEdges(path, top: palette.edgeShade, bottom: nil, in: context)
        } else {
            drawEdges(path, top: palette.edgeLight, bottom: palette.edgeShade, in: context)
        }
        context.setStrokeColor(palette.logo.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.addPath(path.cgPath)
        context.strokePath()
    }

    /// Light or shade just inside a shape's top and bottom edges, fading inward. Each is the shadow
    /// cast into the shape by what's outside it, so it follows any outline. Shadow offsets are in
    /// device space, so a tilted pill is still lit from above.
    private func drawEdges(_ path: UIBezierPath, top: UIColor?, bottom: UIColor?, in context: CGContext) {
        let outside = UIBezierPath(rect: path.bounds.insetBy(dx: -8, dy: -8))
        outside.append(path)
        outside.usesEvenOddFillRule = true
        for (color, offset) in [(top, 1.5), (bottom, -1.5)] as [(UIColor?, CGFloat)] {
            guard let color else { continue }
            context.saveGState()
            context.addPath(path.cgPath)
            context.clip()
            context.setShadow(offset: CGSize(width: 0, height: offset), blur: 2, color: color.cgColor)
            context.setFillColor(UIColor.black.cgColor)
            context.addPath(outside.cgPath)
            context.drawPath(using: .eoFill)
            context.restoreGState()
        }
    }

    /// The lit top of a face: `color` moved a little toward white.
    private func lighter(_ color: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let amount: CGFloat = 0.12
        return UIColor(red: red + (1 - red) * amount, green: green + (1 - green) * amount, blue: blue + (1 - blue) * amount, alpha: alpha)
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

extension TouchHaptics {
    /// The impact intensity for a press, or nil when haptics are off.
    var intensity: CGFloat? {
        switch self {
        case .off: nil
        case .light: 0.55
        case .medium: 0.9
        }
    }
}
