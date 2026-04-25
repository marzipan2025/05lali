import AppKit

private enum AppConstants {
    static let menuBarIconResourceName = "MenuBarIcon"
    static let menuBarIconResourceExtension = "png"
    static let settingsPreviewResourceName = "SettingsPreview"
    static let settingsPreviewResourceExtension = "png"
    static let persistedGridStateKey = "PersistedGridState"
    static let persistedGridStatesByScreenKey = "PersistedGridStatesByScreen"
    static let minimumDisplayedOpacity: Double = 0.2
    static let maximumDisplayedOpacity: Double = 0.9
    static let defaultRows = 3
    static let defaultColumns = 3
    static let defaultLineWidth: CGFloat = 1.0
    static let editHandleWhiteMix: CGFloat = 0.05
    static let editHandleOpacity: CGFloat = 0.23
    static let editHoveredHandleOpacity: CGFloat = 0.10
    static let editHandleStripeWidth: CGFloat = 4.0
    static let editHandleStripeSpacing: CGFloat = 2.5
    static let editHandleStripeAngleDegrees: CGFloat = 45.0
    static let editHandleWidth: CGFloat = 15.0
    static let editPrimaryWidth: CGFloat = 2.0
    static let hoverDistance: CGFloat = 7.0
    static let minNormalizedGap: CGFloat = 0.02
    static let normalTintColor = NSColor(
        calibratedRed: 210.0 / 255.0,
        green: 213.0 / 255.0,
        blue: 225.0 / 255.0,
        alpha: 0.18
    )
    static let normalAdaptiveColor = NSColor.white.withAlphaComponent(0.92)
}

private func bundledResourceURL(
    candidateNames: [String],
    withExtension fileExtension: String
) -> URL? {
    for bundle in [Bundle.main, Bundle.module] {
        for name in candidateNames {
            if let url = bundle.url(forResource: name, withExtension: fileExtension) {
                return url
            }
        }
    }
    return nil
}

private func drawEditHandleStripes(
    in context: CGContext,
    bandRect: NSRect,
    color: NSColor,
    opacity: CGFloat
) {
    guard bandRect.width > 0, bandRect.height > 0 else { return }

    context.saveGState()
    context.clip(to: bandRect)
    context.setBlendMode(.normal)
    context.setStrokeColor(color.withAlphaComponent(opacity).cgColor)
    context.setLineWidth(AppConstants.editHandleStripeWidth)
    context.setLineCap(.butt)

    let angle = AppConstants.editHandleStripeAngleDegrees * .pi / 180
    let dx = cos(angle)
    let dy = sin(angle)
    let nx = -dy
    let ny = dx

    let corners = [
        CGPoint(x: bandRect.minX, y: bandRect.minY),
        CGPoint(x: bandRect.maxX, y: bandRect.minY),
        CGPoint(x: bandRect.maxX, y: bandRect.maxY),
        CGPoint(x: bandRect.minX, y: bandRect.maxY)
    ]
    let projections = corners.map { $0.x * nx + $0.y * ny }
    guard let minP = projections.min(), let maxP = projections.max() else {
        context.restoreGState()
        return
    }

    let period = AppConstants.editHandleStripeWidth + AppConstants.editHandleStripeSpacing
    let length = max(bandRect.width, bandRect.height) * 2

    var t = (floor(minP / period) - 1) * period
    while t <= maxP + period {
        let cx = t * nx
        let cy = t * ny
        context.move(to: CGPoint(x: cx - dx * length, y: cy - dy * length))
        context.addLine(to: CGPoint(x: cx + dx * length, y: cy + dy * length))
        context.strokePath()
        t += period
    }

    context.restoreGState()
}

enum GridAxis: Equatable {
    case horizontal
    case vertical
}

struct HoveredLine: Equatable {
    let axis: GridAxis
    let index: Int
}

struct DragState {
    let axis: GridAxis
    let index: Int
}

struct GridState {
    var horizontalFractions: [CGFloat]
    var verticalFractions: [CGFloat]

    static func evenlyDivided(rows: Int, columns: Int) -> GridState {
        let horizontal = stride(from: 1, to: rows, by: 1).map { CGFloat($0) / CGFloat(rows) }
        let vertical = stride(from: 1, to: columns, by: 1).map { CGFloat($0) / CGFloat(columns) }
        return GridState(horizontalFractions: horizontal, verticalFractions: vertical)
    }

    func sanitized() -> GridState {
        GridState(
            horizontalFractions: sanitize(horizontalFractions),
            verticalFractions: sanitize(verticalFractions)
        )
    }

    private func sanitize(_ fractions: [CGFloat]) -> [CGFloat] {
        fractions
            .map { max(AppConstants.minNormalizedGap, min(1 - AppConstants.minNormalizedGap, $0)) }
            .sorted()
            .reduce(into: [CGFloat]()) { result, value in
                guard let last = result.last else {
                    result.append(value)
                    return
                }

                if value - last >= AppConstants.minNormalizedGap {
                    result.append(value)
                }
            }
    }
}

private struct PersistedGridState: Codable {
    let horizontalFractions: [Double]
    let verticalFractions: [Double]

    init(gridState: GridState) {
        horizontalFractions = gridState.horizontalFractions.map(Double.init)
        verticalFractions = gridState.verticalFractions.map(Double.init)
    }

    var gridState: GridState {
        let horizontal = horizontalFractions.map { CGFloat($0) }
        let vertical = verticalFractions.map { CGFloat($0) }
        let state = GridState(horizontalFractions: horizontal, verticalFractions: vertical)
        return state.sanitized()
    }
}

private enum GridStateStore {
    static func load() -> GridState? {
        guard
            let data = UserDefaults.standard.data(forKey: AppConstants.persistedGridStateKey),
            let persistedState = try? JSONDecoder().decode(PersistedGridState.self, from: data)
        else {
            return nil
        }

        return persistedState.gridState
    }

    static func save(_ gridState: GridState) {
        guard let data = try? JSONEncoder().encode(PersistedGridState(gridState: gridState.sanitized())) else {
            return
        }

        UserDefaults.standard.set(data, forKey: AppConstants.persistedGridStateKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: AppConstants.persistedGridStateKey)
    }
}

private enum MultiGridStateStore {
    static func load() -> [CGDirectDisplayID: GridState] {
        guard
            let data = UserDefaults.standard.data(forKey: AppConstants.persistedGridStatesByScreenKey),
            let persisted = try? JSONDecoder().decode([String: PersistedGridState].self, from: data)
        else {
            return [:]
        }

        var result: [CGDirectDisplayID: GridState] = [:]
        for (key, value) in persisted {
            guard let id = UInt32(key) else { continue }
            result[CGDirectDisplayID(id)] = value.gridState
        }
        return result
    }

    static func save(_ states: [CGDirectDisplayID: GridState]) {
        var persisted: [String: PersistedGridState] = [:]
        for (displayID, state) in states {
            persisted[String(displayID)] = PersistedGridState(gridState: state.sanitized())
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: AppConstants.persistedGridStatesByScreenKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: AppConstants.persistedGridStatesByScreenKey)
    }
}

enum LineColorOption: String, CaseIterable {
    case adaptive
    case blue
    case red
    case yellow

    static func from(id: String) -> LineColorOption {
        LineColorOption(rawValue: id) ?? .adaptive
    }

    var nsColor: NSColor? {
        switch self {
        case .adaptive:
            return nil
        case .blue:
            return NSColor(calibratedRed: 0x00 / 255.0, green: 0x31 / 255.0, blue: 0xE0 / 255.0, alpha: 1.0)
        case .red:
            return NSColor(calibratedRed: 0xE0 / 255.0, green: 0x00 / 255.0, blue: 0x04 / 255.0, alpha: 1.0)
        case .yellow:
            return NSColor(calibratedRed: 0xE0 / 255.0, green: 0xD5 / 255.0, blue: 0x00 / 255.0, alpha: 1.0)
        }
    }
}

enum LineThicknessOption: Double, CaseIterable {
    case extraThin = 0.25
    case thin = 0.5
    case normal = 1.0
    case thick = 2.0
    case extraThick = 3.0

    var label: String {
        switch self {
        case .extraThin: return "0.25"
        case .thin: return "0.5"
        case .normal: return "1.0"
        case .thick: return "2.0"
        case .extraThick: return "3.0"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var opacity: Double
    var lineWidth: Double
    var lineColorID: String

    static let `default` = AppSettings(
        opacity: 0.5,
        lineWidth: LineThicknessOption.normal.rawValue,
        lineColorID: LineColorOption.adaptive.rawValue
    )

    init(opacity: Double, lineWidth: Double, lineColorID: String) {
        self.opacity = opacity
        self.lineWidth = lineWidth
        self.lineColorID = lineColorID
    }

    private enum CodingKeys: String, CodingKey {
        case opacity
        case lineWidth
        case lineColorID
        case legacyNormalColorID = "normalColorID"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try container.decode(Double.self, forKey: .opacity)
        lineWidth = try container.decode(Double.self, forKey: .lineWidth)
        lineColorID = (try? container.decode(String.self, forKey: .lineColorID))
            ?? (try? container.decode(String.self, forKey: .legacyNormalColorID))
            ?? LineColorOption.adaptive.rawValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(lineColorID, forKey: .lineColorID)
    }
}

final class SettingsPreviewView: NSView {
    var gridState = GridState.evenlyDivided(rows: AppConstants.defaultRows, columns: AppConstants.defaultColumns) {
        didSet { needsDisplay = true }
    }

    var settings = AppSettings.default {
        didSet { needsDisplay = true }
    }

    private let backgroundImage: NSImage? = {
        guard let url = bundledResourceURL(
            candidateNames: [AppConstants.settingsPreviewResourceName],
            withExtension: AppConstants.settingsPreviewResourceExtension
        ) else { return nil }
        return NSImage(contentsOf: url)
    }()

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let clipPath = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)

        NSGraphicsContext.current?.saveGraphicsState()
        clipPath.addClip()

        if let image = backgroundImage {
            image.draw(in: aspectFillImageRect(), from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
            bounds.fill()
        }

        if let context = NSGraphicsContext.current?.cgContext {
            drawGrid(in: context, rect: bounds)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func aspectFillImageRect() -> NSRect {
        guard
            let image = backgroundImage,
            image.size.width > 0,
            image.size.height > 0
        else { return bounds }

        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let w = image.size.width * scale
        let h = image.size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    private func drawGrid(in context: CGContext, rect: NSRect) {
        for fraction in gridState.verticalFractions {
            let x = round(rect.minX + rect.width * fraction) + 0.5
            drawLine(in: context, from: CGPoint(x: x, y: rect.minY), to: CGPoint(x: x, y: rect.maxY))
        }

        for fraction in gridState.horizontalFractions {
            let y = round(rect.minY + rect.height * fraction) + 0.5
            drawLine(in: context, from: CGPoint(x: rect.minX, y: y), to: CGPoint(x: rect.maxX, y: y))
        }
    }

    private func drawLine(in context: CGContext, from start: CGPoint, to end: CGPoint) {
        let opacity = CGFloat(settings.opacity)
        let lineWidth = CGFloat(settings.lineWidth) * 0.6
        let option = LineColorOption.from(id: settings.lineColorID)

        if let solidColor = option.nsColor {
            context.saveGState()
            context.setBlendMode(.normal)
            context.setStrokeColor(solidColor.withAlphaComponent(opacity).cgColor)
            context.setLineWidth(lineWidth)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            context.restoreGState()
            return
        }

        let intensity: CGFloat
        if opacity <= 0.5 {
            intensity = 0.1 + 1.8 * opacity
        } else {
            intensity = 1.0 + 2.0 * (opacity - 0.5)
        }

        let tintAlpha = min(1.0, 0.18 * intensity)
        let adaptiveAlpha = min(1.0, 0.92 * intensity)

        context.saveGState()
        context.setBlendMode(.normal)
        context.setStrokeColor(AppConstants.normalTintColor.withAlphaComponent(tintAlpha).cgColor)
        context.setLineWidth(lineWidth + 0.5)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.difference)
        context.setStrokeColor(AppConstants.normalAdaptiveColor.withAlphaComponent(adaptiveAlpha).cgColor)
        context.setLineWidth(lineWidth)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()

        if intensity > 1.0 {
            let darkAlpha = min(0.6, (intensity - 1.0) * 0.5)
            context.saveGState()
            context.setBlendMode(.normal)
            context.setStrokeColor(NSColor.black.withAlphaComponent(darkAlpha).cgColor)
            context.setLineWidth(lineWidth)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            context.restoreGState()
        }
    }

}

private enum AppSettingsStore {
    private static let key = "PersistedAppSettings"

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

protocol GridOverlayViewDelegate: AnyObject {
    func gridOverlayView(_ view: GridOverlayView, hoveredLineDidChange hoveredLine: HoveredLine?)
    func gridOverlayView(_ view: GridOverlayView, didMoveLine hoveredLine: HoveredLine, to normalizedPosition: CGFloat) -> Int?
    func gridOverlayViewDidRequestGridInsertion(atScreenPoint screenPoint: CGPoint)
    func gridOverlayViewDidRequestHoveredLineDeletion()
    func gridOverlayViewDidRequestExitEditing()
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class GridOverlayView: NSView {
    weak var delegate: GridOverlayViewDelegate?

    var gridState = GridState.evenlyDivided(rows: AppConstants.defaultRows, columns: AppConstants.defaultColumns) {
        didSet { needsDisplay = true }
    }

    var isEditing = false {
        didSet {
            if oldValue != isEditing {
                hoveredLine = nil
                dragState = nil
                updateTrackingAreas()
                needsDisplay = true
            }
        }
    }

    var lineWidth: CGFloat = AppConstants.defaultLineWidth {
        didSet { needsDisplay = true }
    }

    var lineOpacity: CGFloat = 0.5 {
        didSet { needsDisplay = true }
    }

    var lineColorOption: LineColorOption = .adaptive {
        didSet { needsDisplay = true }
    }

    private var trackingArea: NSTrackingArea?
    private var hoveredLine: HoveredLine? {
        didSet {
            if oldValue != hoveredLine {
                delegate?.gridOverlayView(self, hoveredLineDidChange: hoveredLine)
                needsDisplay = true
            }
        }
    }
    private var dragState: DragState?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { isEditing }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = isEditing
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let newTrackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        drawVerticalLines(in: context)
        drawHorizontalLines(in: context)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isEditing else { return }
        hoveredLine = hoveredLine(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard isEditing else { return }
        hoveredLine = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        window?.makeFirstResponder(self)
        let localPoint = convert(event.locationInWindow, from: nil)
        let line = hoveredLine(at: localPoint)
        hoveredLine = line
        if let line {
            dragState = DragState(axis: line.axis, index: line.index)
        } else {
            delegate?.gridOverlayViewDidRequestGridInsertion(atScreenPoint: NSEvent.mouseLocation)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing, let dragState else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        let normalizedPosition: CGFloat

        switch dragState.axis {
        case .vertical:
            normalizedPosition = normalizedX(for: localPoint.x)
        case .horizontal:
            normalizedPosition = normalizedY(for: localPoint.y)
        }

        let newIndex = delegate?.gridOverlayView(
            self,
            didMoveLine: HoveredLine(axis: dragState.axis, index: dragState.index),
            to: normalizedPosition
        )

        if let newIndex, newIndex != dragState.index {
            self.dragState = DragState(axis: dragState.axis, index: newIndex)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }
        dragState = nil
        hoveredLine = hoveredLine(at: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        guard isEditing else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            delegate?.gridOverlayViewDidRequestHoveredLineDeletion()
            return
        }

        if event.keyCode == 53 {
            delegate?.gridOverlayViewDidRequestExitEditing()
            return
        }

        super.keyDown(with: event)
    }

    private func drawVerticalLines(in context: CGContext) {
        for (index, fraction) in gridState.verticalFractions.enumerated() {
            let x = round(bounds.width * fraction) + 0.5
            let start = CGPoint(x: x, y: bounds.minY)
            let end = CGPoint(x: x, y: bounds.maxY)
            drawLine(in: context, from: start, to: end, hovered: hoveredLine == HoveredLine(axis: .vertical, index: index))
        }
    }

    private func drawHorizontalLines(in context: CGContext) {
        for (index, fraction) in gridState.horizontalFractions.enumerated() {
            let y = round(bounds.height * fraction) + 0.5
            let start = CGPoint(x: bounds.minX, y: y)
            let end = CGPoint(x: bounds.maxX, y: y)
            drawLine(in: context, from: start, to: end, hovered: hoveredLine == HoveredLine(axis: .horizontal, index: index))
        }
    }

    private func drawLine(in context: CGContext, from startPoint: CGPoint, to endPoint: CGPoint, hovered: Bool) {
        if isEditing {
            let baseColor = lineColorOption.nsColor ?? .white
            let handleColor = baseColor.blended(withFraction: AppConstants.editHandleWhiteMix, of: .white) ?? baseColor
            let bandRect = handleBandRect(start: startPoint, end: endPoint)
            drawEditHandleStripes(
                in: context,
                bandRect: bandRect,
                color: handleColor,
                opacity: hovered ? AppConstants.editHoveredHandleOpacity : AppConstants.editHandleOpacity
            )

            context.saveGState()
            context.setBlendMode(lineColorOption.nsColor == nil ? .difference : .normal)
            let primaryColor = lineColorOption.nsColor ?? .white
            context.setStrokeColor(primaryColor.cgColor)
            context.setLineWidth(AppConstants.editPrimaryWidth)
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
            context.restoreGState()
            return
        }

        if let solidColor = lineColorOption.nsColor {
            context.saveGState()
            context.setBlendMode(.normal)
            context.setStrokeColor(solidColor.withAlphaComponent(lineOpacity).cgColor)
            context.setLineWidth(lineWidth)
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
            context.restoreGState()
            return
        }

        let intensity: CGFloat
        if lineOpacity <= 0.5 {
            intensity = 0.1 + 1.8 * lineOpacity
        } else {
            intensity = 1.0 + 2.0 * (lineOpacity - 0.5)
        }

        let baseTintAlpha: CGFloat = 0.18
        let baseAdaptiveAlpha: CGFloat = 0.92
        let tintAlpha = min(1.0, baseTintAlpha * intensity)
        let adaptiveAlpha = min(1.0, baseAdaptiveAlpha * intensity)

        context.saveGState()
        context.setBlendMode(.normal)
        context.setStrokeColor(AppConstants.normalTintColor.withAlphaComponent(tintAlpha).cgColor)
        context.setLineWidth(lineWidth + 0.5)
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.difference)
        context.setStrokeColor(AppConstants.normalAdaptiveColor.withAlphaComponent(adaptiveAlpha).cgColor)
        context.setLineWidth(lineWidth)
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
        context.restoreGState()

        if intensity > 1.0 {
            let darkAlpha = min(0.6, (intensity - 1.0) * 0.5)
            context.saveGState()
            context.setBlendMode(.normal)
            context.setStrokeColor(NSColor.black.withAlphaComponent(darkAlpha).cgColor)
            context.setLineWidth(lineWidth)
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
            context.restoreGState()
        }
    }

    private func hoveredLine(at point: CGPoint) -> HoveredLine? {
        var bestMatch: (line: HoveredLine, distance: CGFloat)?

        for (index, fraction) in gridState.verticalFractions.enumerated() {
            let x = bounds.width * fraction
            let distance = abs(point.x - x)
            if distance <= AppConstants.hoverDistance,
               bestMatch.map({ distance < $0.distance }) ?? true {
                bestMatch = (HoveredLine(axis: .vertical, index: index), distance)
            }
        }

        for (index, fraction) in gridState.horizontalFractions.enumerated() {
            let y = bounds.height * fraction
            let distance = abs(point.y - y)
            if distance <= AppConstants.hoverDistance,
               bestMatch.map({ distance < $0.distance }) ?? true {
                bestMatch = (HoveredLine(axis: .horizontal, index: index), distance)
            }
        }

        return bestMatch?.line
    }

    private func handleBandRect(start: CGPoint, end: CGPoint) -> NSRect {
        let halfWidth = AppConstants.editHandleWidth / 2
        if abs(start.x - end.x) < 0.5 {
            return NSRect(x: start.x - halfWidth, y: bounds.minY, width: AppConstants.editHandleWidth, height: bounds.height)
        } else {
            return NSRect(x: bounds.minX, y: start.y - halfWidth, width: bounds.width, height: AppConstants.editHandleWidth)
        }
    }

    private func normalizedX(for x: CGFloat) -> CGFloat {
        guard bounds.width > 0 else { return 0.5 }
        return max(0, min(1, x / bounds.width))
    }

    private func normalizedY(for y: CGFloat) -> CGFloat {
        guard bounds.height > 0 else { return 0.5 }
        return max(0, min(1, y / bounds.height))
    }
}

final class ColorSwatchButton: NSButton {
    let swatchID: String
    private let swatchDraw: (NSRect) -> Void
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    init(swatchID: String, swatchDraw: @escaping (NSRect) -> Void) {
        self.swatchID = swatchID
        self.swatchDraw = swatchDraw
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let baseRect = bounds.insetBy(dx: 1, dy: 1)
        let basePath = NSBezierPath(ovalIn: baseRect)
        SettingsStyle.panelBackground.setFill()
        basePath.fill()
        SettingsStyle.swatchBorder.setStroke()
        basePath.lineWidth = 1
        basePath.stroke()

        let swatchRect = bounds.insetBy(dx: 5, dy: 5)
        swatchDraw(swatchRect)

        if isSelected {
            let ringRect = bounds.insetBy(dx: 3, dy: 3)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 1.5
            SettingsStyle.swatchSelection.setStroke()
            ring.stroke()
        }
    }

    static func make(option: LineColorOption, target: AnyObject, action: Selector) -> ColorSwatchButton {
        let button = ColorSwatchButton(swatchID: option.rawValue) { rect in
            let path = NSBezierPath(ovalIn: rect)
            if let color = option.nsColor {
                color.setFill()
                path.fill()
            } else {
                NSGraphicsContext.current?.saveGraphicsState()
                path.addClip()
                NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
                rect.fill()
                let triangle = NSBezierPath()
                triangle.move(to: NSPoint(x: rect.minX, y: rect.maxY))
                triangle.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                triangle.line(to: NSPoint(x: rect.maxX, y: rect.minY))
                triangle.close()
                NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
                triangle.fill()
                NSGraphicsContext.current?.restoreGraphicsState()
                SettingsStyle.swatchBorder.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
        button.target = target
        button.action = action
        return button
    }
}

private enum SettingsStyle {
    static let windowBackground = NSColor(calibratedWhite: 0.965, alpha: 1.0)
    static let panelBackground = NSColor(calibratedWhite: 0.94, alpha: 1.0)
    static let panelStroke = NSColor.black.withAlphaComponent(0.08)
    static let divider = NSColor.black.withAlphaComponent(0.08)
    static let primaryText = NSColor(calibratedWhite: 0.16, alpha: 1.0)
    static let secondaryText = NSColor(calibratedWhite: 0.38, alpha: 1.0)
    static let swatchBorder = NSColor.black.withAlphaComponent(0.14)
    static let swatchSelection = NSColor.black.withAlphaComponent(0.72)
    static let destructiveAccent = NSColor.systemRed
    static let panelCornerRadius: CGFloat = 12
    static let previewCornerRadius: CGFloat = 18
}

final class SettingsViewController: NSViewController {
    private let overlayController: OverlayController
    private let previewView = SettingsPreviewView()
    private var opacitySlider: NSSlider!
    private var thicknessSlider: NSSlider!
    private var colorButtons: [ColorSwatchButton] = []
    private var lineSection: NSView!
    private var colorSection: NSView!
    private var resetActionButton: NSButton!
    private var resetConfirmButton: NSButton!
    private var resetActionButtonWidthConstraint: NSLayoutConstraint?
    private var resetConfirmButtonWidthConstraint: NSLayoutConstraint?
    private var isResetConfirmationVisible = false

    init(overlayController: OverlayController) {
        self.overlayController = overlayController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 552))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = SettingsStyle.windowBackground.cgColor

        let titleLabel = NSTextField(labelWithString: "Settings")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = SettingsStyle.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = SettingsStyle.previewCornerRadius
        previewView.layer?.cornerCurve = .continuous
        previewView.layer?.borderWidth = 1
        previewView.layer?.borderColor = SettingsStyle.panelStroke.cgColor

        lineSection = makeLineGroup()
        colorSection = makeColorGroup()

        let groupsStack = NSStackView(views: [lineSection, colorSection])
        groupsStack.orientation = .vertical
        groupsStack.alignment = .leading
        groupsStack.spacing = 18
        groupsStack.translatesAutoresizingMaskIntoConstraints = false

        let resetSection = makeResetSection()
        resetSection.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(titleLabel)
        rootView.addSubview(previewView)
        rootView.addSubview(groupsStack)
        rootView.addSubview(resetSection)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -20),

            previewView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            previewView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            previewView.heightAnchor.constraint(equalToConstant: 210),

            groupsStack.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 20),
            groupsStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            groupsStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            lineSection.leadingAnchor.constraint(equalTo: groupsStack.leadingAnchor),
            lineSection.trailingAnchor.constraint(equalTo: groupsStack.trailingAnchor),
            colorSection.leadingAnchor.constraint(equalTo: groupsStack.leadingAnchor),
            colorSection.trailingAnchor.constraint(equalTo: groupsStack.trailingAnchor),

            resetSection.topAnchor.constraint(equalTo: groupsStack.bottomAnchor, constant: 22),
            resetSection.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            resetSection.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -20),
            resetSection.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20)
        ])

        self.view = rootView
        updateResetButtons()
        refreshFromSettings()
    }

    private func makeLineGroup() -> NSView {
        let opacitySliderControl = NSSlider(
            value: 0.5,
            minValue: AppConstants.minimumDisplayedOpacity,
            maxValue: AppConstants.maximumDisplayedOpacity,
            target: self,
            action: #selector(opacityChanged(_:))
        )
        opacitySliderControl.isContinuous = true
        opacitySliderControl.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider = opacitySliderControl

        let stepCount = LineThicknessOption.allCases.count
        let thickness = NSSlider(
            value: 0,
            minValue: 0,
            maxValue: Double(stepCount - 1),
            target: self,
            action: #selector(thicknessChanged(_:))
        )
        thickness.numberOfTickMarks = stepCount
        thickness.allowsTickMarkValuesOnly = true
        thickness.tickMarkPosition = .below
        thickness.isContinuous = true
        thickness.translatesAutoresizingMaskIntoConstraints = false
        thicknessSlider = thickness

        let opacityRow = makeRow(label: "Line Opacity", control: opacitySliderControl, controlWidth: 200)
        let thicknessRow = makeRow(label: "Line Thickness", control: thickness, controlWidth: 200)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(opacityRow)
        let divider = makeDivider()
        container.addSubview(divider)
        container.addSubview(thicknessRow)

        NSLayoutConstraint.activate([
            opacityRow.topAnchor.constraint(equalTo: container.topAnchor),
            opacityRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            opacityRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            divider.topAnchor.constraint(equalTo: opacityRow.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1),

            thicknessRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            thicknessRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thicknessRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            thicknessRow.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return makeSection(title: "Line", containing: container)
    }

    private func makeColorGroup() -> NSView {
        colorButtons = LineColorOption.allCases.map { option in
            ColorSwatchButton.make(option: option, target: self, action: #selector(colorTapped(_:)))
        }

        let buttonsStack = NSStackView(views: colorButtons)
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 10
        buttonsStack.alignment = .centerY
        buttonsStack.distribution = .gravityAreas
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.setContentHuggingPriority(.required, for: .horizontal)

        let colorRow = makeRow(label: "Line Color", control: buttonsStack, controlWidth: nil)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(colorRow)

        NSLayoutConstraint.activate([
            colorRow.topAnchor.constraint(equalTo: container.topAnchor),
            colorRow.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            colorRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            colorRow.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return makeSection(title: "Color", containing: container)
    }

    private func makeRow(label text: String, control: NSView, controlWidth: CGFloat?) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = makeRowLabel(text)

        row.addSubview(label)
        row.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false

        var constraints: [NSLayoutConstraint] = [
            row.heightAnchor.constraint(equalToConstant: 52),

            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12)
        ]
        if let width = controlWidth {
            constraints.append(control.widthAnchor.constraint(equalToConstant: width))
        }
        NSLayoutConstraint.activate(constraints)
        return row
    }

    private func makeRowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .left
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = SettingsStyle.primaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func makeSection(title: String, containing subview: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = SettingsStyle.secondaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = SettingsStyle.panelBackground.cgColor
        panel.layer?.cornerRadius = SettingsStyle.panelCornerRadius
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = SettingsStyle.panelStroke.cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: panel.topAnchor, constant: 2),
            subview.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -2),
            subview.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: panel.trailingAnchor)
        ])

        let section = NSStackView(views: [titleLabel, panel])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        section.translatesAutoresizingMaskIntoConstraints = false
        return section
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = SettingsStyle.divider.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        return divider
    }

    private func makeResetSection() -> NSView {
        let descriptionLabel = NSTextField(wrappingLabelWithString: "This will permanently reset line opacity, line thickness, line color, and all saved grid layouts. It cannot be undone.")
        descriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        descriptionLabel.textColor = SettingsStyle.secondaryText
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        resetActionButton = makeFooterButton(title: "Reset Settings", backgroundColor: NSColor(calibratedWhite: 0.985, alpha: 1.0), foregroundColor: SettingsStyle.primaryText, borderColor: SettingsStyle.panelStroke)
        resetActionButton.target = self
        resetActionButton.action = #selector(toggleResetConfirmation(_:))
        resetActionButtonWidthConstraint = resetActionButton.widthAnchor.constraint(equalToConstant: footerButtonWidth(for: resetActionButton.title))
        resetActionButtonWidthConstraint?.isActive = true

        resetConfirmButton = makeFooterButton(title: "Are you sure?", backgroundColor: SettingsStyle.destructiveAccent, foregroundColor: .white, borderColor: nil)
        resetConfirmButton.target = self
        resetConfirmButton.action = #selector(confirmResetAll(_:))
        resetConfirmButtonWidthConstraint = resetConfirmButton.widthAnchor.constraint(equalToConstant: footerButtonWidth(for: resetConfirmButton.title))
        resetConfirmButtonWidthConstraint?.isActive = true

        let buttonsStack = NSStackView(views: [resetActionButton, resetConfirmButton])
        buttonsStack.orientation = .horizontal
        buttonsStack.alignment = .centerY
        buttonsStack.spacing = 10
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView(views: [descriptionLabel, buttonsStack])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }

    private func makeFooterButton(title: String, backgroundColor: NSColor, foregroundColor: NSColor, borderColor: NSColor?) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = foregroundColor
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.alignment = .center
        button.wantsLayer = true
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.layer?.cornerRadius = 10
        button.layer?.cornerCurve = .continuous
        button.layer?.borderWidth = borderColor == nil ? 0 : 1
        button.layer?.borderColor = borderColor?.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func footerButtonWidth(for title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        return textWidth + 20
    }

    private func updateResetButtons() {
        resetActionButton.title = isResetConfirmationVisible ? "Cancel" : "Reset Settings"
        resetActionButtonWidthConstraint?.constant = footerButtonWidth(for: resetActionButton.title)
        resetConfirmButtonWidthConstraint?.constant = footerButtonWidth(for: resetConfirmButton.title)
        resetConfirmButton.isHidden = !isResetConfirmationVisible
    }

    private func refreshFromSettings() {
        let s = overlayController.settings
        opacitySlider.doubleValue = s.opacity
        previewView.gridState = overlayController.currentGridState
        previewView.settings = s
        let thicknessIndex = LineThicknessOption.allCases.firstIndex(where: { $0.rawValue == s.lineWidth })
            ?? LineThicknessOption.allCases.firstIndex(of: .normal)
            ?? 2
        thicknessSlider.doubleValue = Double(thicknessIndex)
        let current = LineColorOption.from(id: s.lineColorID)
        for button in colorButtons {
            button.isSelected = (button.swatchID == current.rawValue)
        }
    }

    func prepareForDisplay() {
        refreshFromSettings()
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        var s = overlayController.settings
        s.opacity = sender.doubleValue
        overlayController.settings = s
        previewView.settings = s
    }

    @objc private func thicknessChanged(_ sender: NSSlider) {
        let idx = Int(sender.doubleValue.rounded())
        guard LineThicknessOption.allCases.indices.contains(idx) else { return }
        var s = overlayController.settings
        s.lineWidth = LineThicknessOption.allCases[idx].rawValue
        overlayController.settings = s
        previewView.settings = s
    }

    @objc private func colorTapped(_ sender: ColorSwatchButton) {
        var s = overlayController.settings
        s.lineColorID = sender.swatchID
        overlayController.settings = s
        previewView.settings = s
        for button in colorButtons {
            button.isSelected = (button.swatchID == sender.swatchID)
        }
    }

    @objc private func toggleResetConfirmation(_ sender: NSButton) {
        isResetConfirmationVisible.toggle()
        updateResetButtons()
    }

    @objc private func confirmResetAll(_ sender: NSButton) {
        overlayController.resetAll()
        isResetConfirmationVisible = false
        updateResetButtons()
        refreshFromSettings()
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onWindowVisibilityChanged: ((Bool) -> Void)?

    init(overlayController: OverlayController) {
        let settingsViewController = SettingsViewController(overlayController: overlayController)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 552),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = SettingsStyle.windowBackground
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.contentViewController = settingsViewController
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        (window?.contentViewController as? SettingsViewController)?.prepareForDisplay()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onWindowVisibilityChanged?(true)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowVisibilityChanged?(false)
    }
}

final class OverlayController: NSObject {
    private var windowsByScreenID: [CGDirectDisplayID: OverlayWindow] = [:]
    private var gridStatesByScreenID: [CGDirectDisplayID: GridState] = {
        let multi = MultiGridStateStore.load()
        if !multi.isEmpty { return multi }
        // Legacy migration: seed every current screen with the single saved grid state.
        let legacy = GridStateStore.load() ?? GridState.evenlyDivided(
            rows: AppConstants.defaultRows,
            columns: AppConstants.defaultColumns
        )
        var seeded: [CGDirectDisplayID: GridState] = [:]
        for screen in NSScreen.screens {
            if let id = OverlayController.displayID(for: screen) {
                seeded[id] = legacy
            }
        }
        if !seeded.isEmpty {
            MultiGridStateStore.save(seeded)
        }
        return seeded
    }()

    var settings: AppSettings = AppSettingsStore.load() {
        didSet {
            AppSettingsStore.save(settings)
            updateViews()
        }
    }
    var isSuppressedForSettings = false {
        didSet {
            updateOverlayVisibility()
        }
    }
    var onEditingChanged: (() -> Void)?
    private var hoveredLocation: HoveredLocation? {
        didSet { updateViews() }
    }

    /// Display the menu actions should target. Set by the app delegate when the menu opens.
    var activeDisplayID: CGDirectDisplayID?

    var isEnabled = false {
        didSet {
            if !isEnabled, isEditing {
                isEditing = false
            }
            refreshWindows()
        }
    }

    var isEditing = false {
        didSet {
            guard isEnabled else {
                if isEditing { isEditing = false }
                return
            }
            hoveredLocation = nil
            updateWindowInteraction()
            updateViews()
            focusEditableWindowIfNeeded()
        }
    }

    var rows: Int {
        resolvedGridState(for: activeDisplayID).horizontalFractions.count + 1
    }

    var columns: Int {
        resolvedGridState(for: activeDisplayID).verticalFractions.count + 1
    }

    var currentGridState: GridState {
        resolvedGridState(for: activeDisplayID ?? primaryDisplayID)
    }

    private struct HoveredLocation: Equatable {
        let displayID: CGDirectDisplayID
        let line: HoveredLine
    }

    private var primaryDisplayID: CGDirectDisplayID? {
        if let main = NSScreen.main, let id = Self.displayID(for: main) {
            return id
        }
        return windowsByScreenID.keys.first
    }

    private func resolvedGridState(for displayID: CGDirectDisplayID?) -> GridState {
        if let displayID, let state = gridStatesByScreenID[displayID] {
            return state
        }
        return GridState.evenlyDivided(
            rows: AppConstants.defaultRows,
            columns: AppConstants.defaultColumns
        )
    }

    private func mutateGridState(
        for displayID: CGDirectDisplayID,
        _ transform: (inout GridState) -> Void
    ) {
        var state = resolvedGridState(for: displayID)
        transform(&state)
        gridStatesByScreenID[displayID] = state
        MultiGridStateStore.save(gridStatesByScreenID)
        updateViews()
    }

    private func displayID(for view: GridOverlayView) -> CGDirectDisplayID? {
        guard let window = view.window else { return nil }
        for (id, candidate) in windowsByScreenID where candidate === window {
            return id
        }
        return nil
    }

    func updateActiveDisplayForMouseLocation() {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           let id = Self.displayID(for: screen) {
            activeDisplayID = id
        } else {
            activeDisplayID = primaryDisplayID
        }
    }

    override init() {
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func setRows(_ rows: Int) {
        guard let id = activeDisplayID ?? primaryDisplayID else { return }
        mutateGridState(for: id) { state in
            state.horizontalFractions = evenlySpacedFractions(sections: rows)
        }
    }

    func setColumns(_ columns: Int) {
        guard let id = activeDisplayID ?? primaryDisplayID else { return }
        mutateGridState(for: id) { state in
            state.verticalFractions = evenlySpacedFractions(sections: columns)
        }
    }

    func resetGrid() {
        guard let id = activeDisplayID ?? primaryDisplayID else { return }
        mutateGridState(for: id) { state in
            state = GridState.evenlyDivided(
                rows: AppConstants.defaultRows,
                columns: AppConstants.defaultColumns
            )
        }
    }

    func resetAll() {
        let defaultState = GridState.evenlyDivided(
            rows: AppConstants.defaultRows,
            columns: AppConstants.defaultColumns
        )
        gridStatesByScreenID = gridStatesByScreenID.mapValues { _ in defaultState }
        for screen in NSScreen.screens {
            if let id = Self.displayID(for: screen) {
                gridStatesByScreenID[id] = defaultState
            }
        }
        MultiGridStateStore.save(gridStatesByScreenID)
        settings = .default
        GridStateStore.clear()
        AppSettingsStore.clear()
        updateViews()
    }

    @objc private func handleScreenChange() {
        refreshWindows()
    }

    private func refreshWindows() {
        guard isEnabled else {
            closeAllWindows()
            return
        }

        let activeScreens = NSScreen.screens
        let activeIDs = Set(activeScreens.compactMap(Self.displayID(for:)))

        for (displayID, window) in windowsByScreenID where !activeIDs.contains(displayID) {
            window.orderOut(nil)
            windowsByScreenID.removeValue(forKey: displayID)
        }

        var seededNew = false
        for screen in activeScreens {
            guard let displayID = Self.displayID(for: screen) else { continue }

            let window = windowsByScreenID[displayID] ?? makeWindow(for: screen)
            if windowsByScreenID[displayID] == nil {
                windowsByScreenID[displayID] = window
            }

            if gridStatesByScreenID[displayID] == nil {
                gridStatesByScreenID[displayID] = GridState.evenlyDivided(
                    rows: AppConstants.defaultRows,
                    columns: AppConstants.defaultColumns
                )
                seededNew = true
            }

            window.setFrame(overlayFrame(for: screen), display: true)
            if let view = window.contentView as? GridOverlayView {
                view.frame = window.contentLayoutRect
            }
        }

        if seededNew {
            MultiGridStateStore.save(gridStatesByScreenID)
        }

        updateWindowInteraction()
        updateViews()
        updateOverlayVisibility()
        focusEditableWindowIfNeeded()
    }

    private func updateViews() {
        let option = LineColorOption.from(id: settings.lineColorID)
        for (displayID, window) in windowsByScreenID {
            guard let view = window.contentView as? GridOverlayView else { continue }
            view.gridState = resolvedGridState(for: displayID)
            view.isEditing = isEditing
            view.lineWidth = CGFloat(settings.lineWidth)
            view.lineOpacity = CGFloat(settings.opacity)
            view.lineColorOption = option
        }
    }

    private func updateOverlayVisibility() {
        for (_, window) in windowsByScreenID {
            if isEnabled && !isSuppressedForSettings {
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }
    }

    private func updateWindowInteraction() {
        for (_, window) in windowsByScreenID {
            window.ignoresMouseEvents = !isEditing
            window.acceptsMouseMovedEvents = isEditing
            window.level = isEditing ? .statusBar : .screenSaver
            if let view = window.contentView as? GridOverlayView {
                view.isEditing = isEditing
            }
        }
    }

    private func focusEditableWindowIfNeeded() {
        guard isEnabled, isEditing, !isSuppressedForSettings else { return }

        let mouseLocation = NSEvent.mouseLocation
        let preferredWindow = windowsByScreenID.values.first { $0.frame.contains(mouseLocation) } ?? windowsByScreenID.values.first
        preferredWindow?.makeKeyAndOrderFront(nil)
        if let view = preferredWindow?.contentView as? GridOverlayView {
            preferredWindow?.makeFirstResponder(view)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeAllWindows() {
        for (_, window) in windowsByScreenID {
            window.orderOut(nil)
        }
    }

    private func makeWindow(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: overlayFrame(for: screen),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        let view = GridOverlayView(frame: overlayFrame(for: screen))
        view.delegate = self
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }

    private func overlayFrame(for screen: NSScreen) -> NSRect {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = max(0, fullFrame.maxY - visibleFrame.maxY)

        guard menuBarHeight > 0 else {
            return fullFrame
        }

        return NSRect(
            x: fullFrame.minX,
            y: fullFrame.minY,
            width: fullFrame.width,
            height: fullFrame.height - menuBarHeight
        )
    }

    private func evenlySpacedFractions(sections: Int) -> [CGFloat] {
        guard sections > 1 else { return [] }
        return stride(from: 1, to: sections, by: 1).map { CGFloat($0) / CGFloat(sections) }
    }

    @discardableResult
    private func updateLine(
        _ line: HoveredLine,
        to normalizedPosition: CGFloat,
        on displayID: CGDirectDisplayID
    ) -> Int? {
        let resolvedPosition = globallyClamped(normalizedPosition)
        var movedLine: HoveredLine?
        mutateGridState(for: displayID) { state in
            switch line.axis {
            case .vertical:
                guard state.verticalFractions.indices.contains(line.index) else { return }
                state.verticalFractions[line.index] = resolvedPosition
                state.verticalFractions.sort()
                movedLine = Self.nearestLine(
                    in: state.verticalFractions,
                    axis: .vertical,
                    target: resolvedPosition
                )
            case .horizontal:
                guard state.horizontalFractions.indices.contains(line.index) else { return }
                state.horizontalFractions[line.index] = resolvedPosition
                state.horizontalFractions.sort()
                movedLine = Self.nearestLine(
                    in: state.horizontalFractions,
                    axis: .horizontal,
                    target: resolvedPosition
                )
            }
        }
        if let movedLine {
            hoveredLocation = HoveredLocation(displayID: displayID, line: movedLine)
        } else {
            hoveredLocation = nil
        }
        return movedLine?.index
    }

    private static func nearestLine(in positions: [CGFloat], axis: GridAxis, target: CGFloat) -> HoveredLine? {
        guard let index = positions.enumerated().min(by: {
            abs($0.element - target) < abs($1.element - target)
        })?.offset else {
            return nil
        }
        return HoveredLine(axis: axis, index: index)
    }

    private func globallyClamped(_ position: CGFloat) -> CGFloat {
        max(AppConstants.minNormalizedGap, min(1 - AppConstants.minNormalizedGap, position))
    }

    private func insertLines(atScreenPoint screenPoint: CGPoint) {
        guard !isHoveringAnyLine else {
            return
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? NSScreen.main,
              let displayID = Self.displayID(for: screen)
        else {
            return
        }

        let screenFrame = screen.frame
        let normalizedX = max(
            AppConstants.minNormalizedGap,
            min(1 - AppConstants.minNormalizedGap, (screenPoint.x - screenFrame.minX) / screenFrame.width)
        )
        let normalizedY = max(
            AppConstants.minNormalizedGap,
            min(1 - AppConstants.minNormalizedGap, (screenPoint.y - screenFrame.minY) / screenFrame.height)
        )

        mutateGridState(for: displayID) { state in
            Self.insertLine(at: normalizedX, axis: .vertical, into: &state)
            Self.insertLine(at: normalizedY, axis: .horizontal, into: &state)
        }
    }

    private static func insertLine(at normalizedPosition: CGFloat, axis: GridAxis, into state: inout GridState) {
        switch axis {
        case .vertical:
            guard !state.verticalFractions.contains(where: { abs($0 - normalizedPosition) < AppConstants.minNormalizedGap }) else {
                return
            }
            state.verticalFractions.append(normalizedPosition)
            state.verticalFractions.sort()
        case .horizontal:
            guard !state.horizontalFractions.contains(where: { abs($0 - normalizedPosition) < AppConstants.minNormalizedGap }) else {
                return
            }
            state.horizontalFractions.append(normalizedPosition)
            state.horizontalFractions.sort()
        }
    }

    private func deleteHoveredLine() {
        guard let location = hoveredLocation else { return }

        mutateGridState(for: location.displayID) { state in
            switch location.line.axis {
            case .vertical:
                guard state.verticalFractions.indices.contains(location.line.index) else { return }
                state.verticalFractions.remove(at: location.line.index)
            case .horizontal:
                guard state.horizontalFractions.indices.contains(location.line.index) else { return }
                state.horizontalFractions.remove(at: location.line.index)
            }
        }

        hoveredLocation = nil
    }

    private var isHoveringAnyLine: Bool {
        hoveredLocation != nil
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

extension OverlayController: GridOverlayViewDelegate {
    func gridOverlayView(_ view: GridOverlayView, hoveredLineDidChange hoveredLine: HoveredLine?) {
        if let hoveredLine, let id = displayID(for: view) {
            hoveredLocation = HoveredLocation(displayID: id, line: hoveredLine)
        } else {
            hoveredLocation = nil
        }
    }

    func gridOverlayView(_ view: GridOverlayView, didMoveLine hoveredLine: HoveredLine, to normalizedPosition: CGFloat) -> Int? {
        guard let id = displayID(for: view) else { return nil }
        return updateLine(hoveredLine, to: normalizedPosition, on: id)
    }

    func gridOverlayViewDidRequestGridInsertion(atScreenPoint screenPoint: CGPoint) {
        insertLines(atScreenPoint: screenPoint)
    }

    func gridOverlayViewDidRequestHoveredLineDeletion() {
        deleteHoveredLine()
    }

    func gridOverlayViewDidRequestExitEditing() {
        guard isEditing else { return }
        isEditing = false
        onEditingChanged?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayController = OverlayController()
    private lazy var settingsWindowController = SettingsWindowController(overlayController: overlayController)
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!

    private let rowOptions = [2, 3, 4, 5, 6]
    private let columnOptions = [2, 3, 4, 5, 6]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        settingsWindowController.onWindowVisibilityChanged = { [weak self] isVisible in
            self?.overlayController.isSuppressedForSettings = isVisible
        }
        overlayController.onEditingChanged = { [weak self] in
            self?.rebuildMenu()
        }
        overlayController.isEnabled = true
        rebuildMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = makeMenuBarImage()
            button.image?.isTemplate = true
            button.imageScaling = .scaleProportionallyDown
        }

        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildMenu()
    }

    private func makeMenuBarImage() -> NSImage {
        if let resourceURL = bundledResourceURL(
            candidateNames: [AppConstants.menuBarIconResourceName, "menubarIcon_05lali_2"],
            withExtension: AppConstants.menuBarIconResourceExtension
        ),
           let image = NSImage(contentsOf: resourceURL) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "square.split.2x2",
            accessibilityDescription: "05lali"
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    private func rebuildMenu() {
        guard let menu = statusMenu else { return }
        menu.removeAllItems()

        let enabledItem = NSMenuItem(
            title: overlayController.isEnabled ? "Turn Grid Off" : "Turn Grid On",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        enabledItem.target = self
        menu.addItem(enabledItem)

        if overlayController.isEnabled {
            let editItem = NSMenuItem(
                title: overlayController.isEditing ? "Grid Edit Off" : "Grid Edit On",
                action: #selector(toggleEditMode),
                keyEquivalent: ""
            )
            editItem.target = self
            menu.addItem(editItem)
        }

        menu.addItem(.separator())
        menu.addItem(makeRowsMenuItem())
        menu.addItem(makeColumnsMenuItem())

        let resetItem = NSMenuItem(title: "Reset to 3 x 3", action: #selector(resetGrid), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit 05lali", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
    }

    private func makeRowsMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Rows", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for value in rowOptions {
            let item = NSMenuItem(
                title: "\(value) sections",
                action: #selector(selectRows(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = overlayController.rows == value ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        return parent
    }

    private func makeColumnsMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Columns", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for value in columnOptions {
            let item = NSMenuItem(
                title: "\(value) sections",
                action: #selector(selectColumns(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = overlayController.columns == value ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        return parent
    }

    @objc private func toggleOverlay() {
        overlayController.isEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleEditMode() {
        overlayController.isEditing.toggle()
        rebuildMenu()
    }

    @objc private func resetGrid() {
        overlayController.resetGrid()
        rebuildMenu()
    }

    @objc private func selectRows(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        overlayController.setRows(value)
        rebuildMenu()
    }

    @objc private func selectColumns(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        overlayController.setColumns(value)
        rebuildMenu()
    }

    @objc private func openSettings() {
        settingsWindowController.showWindowAndActivate()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        overlayController.updateActiveDisplayForMouseLocation()
        if !overlayController.isEnabled {
            overlayController.isEnabled = true
        }
        rebuildMenu()
    }
}

@main
struct GridOverlayApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
