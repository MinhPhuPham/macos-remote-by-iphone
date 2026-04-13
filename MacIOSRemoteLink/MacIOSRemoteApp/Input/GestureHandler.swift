import UIKit

/// Translates iOS touch gestures into macOS mouse/scroll events.
///
/// Gesture mapping:
///   - One-finger tap        → left click
///   - One-finger double tap → double click
///   - One-finger pan        → move cursor (or pan when zoomed)
///   - Two-finger tap        → right click
///   - Two-finger pan        → scroll wheel
///   - Two-finger double tap → reset zoom
///   - Long press + drag     → click-and-drag
///   - Pinch                 → zoom in/out (1x–5x)
///
/// Coordinate mapping accounts for:
///   1. Aspect-fit letterboxing (AVSampleBufferDisplayLayer.resizeAspect)
///   2. UIView.transform (zoom/pan) — handled automatically by gesture.location(in:)
final class GestureHandler: NSObject, UIGestureRecognizerDelegate {

    var onMouseEvent: ((MouseEventType, CGPoint) -> Void)?
    var onScrollEvent: ((CGFloat, CGFloat) -> Void)?

    var serverScreenWidth: CGFloat = 1920
    var serverScreenHeight: CGFloat = 1080

    private(set) var zoomScale: CGFloat = 1.0
    private var panOffset: CGPoint = .zero

    private weak var targetView: VideoDisplayUIView?
    private var isDragging = false

    private let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private let mediumFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let heavyFeedback = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Setup

    func attach(to view: VideoDisplayUIView) {
        if let old = targetView {
            old.gestureRecognizers?.forEach { old.removeGestureRecognizer($0) }
        }
        targetView = view
        view.isMultipleTouchEnabled = true

        lightFeedback.prepare()
        mediumFeedback.prepare()
        heavyFeedback.prepare()

        // --- Taps ---

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.numberOfTouchesRequired = 1
        singleTap.delegate = self

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.delegate = self

        let twoFingerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerDoubleTap))
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerDoubleTap.numberOfTouchesRequired = 2

        // --- Continuous ---

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.4
        longPress.delegate = self

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = self

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.delegate = self

        // --- Dependencies ---

        // Tap only fires if pan didn't recognize (prevents click-on-drag).
        singleTap.require(toFail: pan)
        singleTap.require(toFail: doubleTap)
        singleTap.require(toFail: longPress)
        twoFingerTap.require(toFail: twoFingerDoubleTap)
        twoFingerTap.require(toFail: scroll)

        // --- Add all ---
        for g in [singleTap, doubleTap, twoFingerTap, twoFingerDoubleTap,
                  pan, longPress, scroll, pinch] as [UIGestureRecognizer] {
            view.addGestureRecognizer(g)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Allow pinch + scroll to fire simultaneously (both use 2 fingers).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let isPinch = gestureRecognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
        let isScroll = (gestureRecognizer.numberOfTouches >= 2 && gestureRecognizer is UIPanGestureRecognizer)
                    || (other.numberOfTouches >= 2 && other is UIPanGestureRecognizer)
        if isPinch && isScroll { return true }
        return false
    }

    // MARK: - Zoom

    private func applyTransform() {
        guard let view = targetView else { return }
        view.transform = CGAffineTransform.identity
            .translatedBy(x: panOffset.x, y: panOffset.y)
            .scaledBy(x: zoomScale, y: zoomScale)
    }

    func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
        UIView.animate(withDuration: 0.25) { [self] in
            applyTransform()
        }
    }

    // MARK: - Coordinate Translation

    func convertToServerCoordinates(_ touchPoint: CGPoint) -> CGPoint {
        guard let view = targetView else { return .zero }
        let videoRect = view.videoRect(forScreenWidth: serverScreenWidth, screenHeight: serverScreenHeight)
        guard videoRect.width > 0, videoRect.height > 0 else { return .zero }

        let relX = (touchPoint.x - videoRect.origin.x) / videoRect.width
        let relY = (touchPoint.y - videoRect.origin.y) / videoRect.height

        return CGPoint(
            x: max(0, min(serverScreenWidth, relX * serverScreenWidth)),
            y: max(0, min(serverScreenHeight, relY * serverScreenHeight))
        )
    }

    // MARK: - Tap Handlers

    @objc private func handleSingleTap(_ g: UITapGestureRecognizer) {
        let p = convertToServerCoordinates(g.location(in: targetView))
        onMouseEvent?(.leftDown, p)
        onMouseEvent?(.leftUp, p)
        lightFeedback.impactOccurred()
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        let p = convertToServerCoordinates(g.location(in: targetView))
        onMouseEvent?(.leftDown, p)
        onMouseEvent?(.leftUp, p)
        onMouseEvent?(.leftDown, p)
        onMouseEvent?(.leftUp, p)
        mediumFeedback.impactOccurred()
    }

    @objc private func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
        let p = convertToServerCoordinates(g.location(in: targetView))
        onMouseEvent?(.rightDown, p)
        onMouseEvent?(.rightUp, p)
        lightFeedback.impactOccurred()
    }

    @objc private func handleTwoFingerDoubleTap(_ g: UITapGestureRecognizer) {
        resetZoom()
        mediumFeedback.impactOccurred()
    }

    // MARK: - Continuous Handlers

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        if isDragging { return }

        // When zoomed: pan the view instead of moving cursor.
        if zoomScale > 1.01 {
            guard let superview = targetView?.superview else { return }
            if g.state == .changed {
                let t = g.translation(in: superview)
                panOffset.x += t.x
                panOffset.y += t.y
                g.setTranslation(.zero, in: superview)
                applyTransform()
            }
            return
        }

        // Not zoomed: move cursor.
        let p = convertToServerCoordinates(g.location(in: targetView))
        if g.state == .began || g.state == .changed {
            onMouseEvent?(.move, p)
        }
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        let p = convertToServerCoordinates(g.location(in: targetView))
        switch g.state {
        case .began:
            isDragging = true
            onMouseEvent?(.leftDown, p)
            heavyFeedback.impactOccurred()
        case .changed:
            onMouseEvent?(.move, p)
        case .ended, .cancelled:
            onMouseEvent?(.leftUp, p)
            isDragging = false
        default: break
        }
    }

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        guard let view = targetView else { return }
        if g.state == .changed {
            let t = g.translation(in: view)
            onScrollEvent?(t.x, t.y)
            g.setTranslation(.zero, in: view)
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .changed:
            zoomScale = max(1.0, min(5.0, zoomScale * g.scale))
            g.scale = 1.0
            if zoomScale <= 1.01 { panOffset = .zero }
            applyTransform()
        case .ended:
            if zoomScale <= 1.01 { resetZoom() }
        default: break
        }
    }
}
