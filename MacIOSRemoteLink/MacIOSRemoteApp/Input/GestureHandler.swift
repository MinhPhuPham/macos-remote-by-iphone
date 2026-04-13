import os
import UIKit

/// Translates iOS touch gestures into macOS mouse/scroll events.
///
/// Gesture model:
///   - Tap          → click at position (leftDown + leftUp)
///   - Double tap   → double click
///   - Two-finger tap → right click
///   - One-finger drag → move cursor (NO click)
///   - Long press + drag → click-and-drag
///   - Two-finger drag → scroll wheel
///   - Pinch        → zoom display (1x–5x)
///   - Two-finger double tap → reset zoom
///
/// Zoom is applied to the CALayer (not UIView.transform) so SwiftUI layout doesn't reset it.
/// Coordinate mapping manually inverses the zoom/pan to get correct Mac screen positions.
final class GestureHandler: NSObject, UIGestureRecognizerDelegate {

    var onMouseEvent: ((MouseEventType, CGPoint) -> Void)?
    var onScrollEvent: ((CGFloat, CGFloat) -> Void)?

    var serverScreenWidth: CGFloat = 1920
    var serverScreenHeight: CGFloat = 1080

    private(set) var zoomScale: CGFloat = 1.0
    private var panOffset: CGPoint = .zero

    private weak var targetView: VideoDisplayUIView?
    private var isDragging = false

    private let tapFeedback = UIImpactFeedbackGenerator(style: .light)
    private let dragFeedback = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Setup

    func attach(to view: VideoDisplayUIView) {
        if let old = targetView {
            old.gestureRecognizers?.forEach { old.removeGestureRecognizer($0) }
        }
        targetView = view
        view.isMultipleTouchEnabled = true
        view.clipsToBounds = true  // Clip zoomed content to view bounds.
        tapFeedback.prepare()
        dragFeedback.prepare()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        let resetZoomTap = UITapGestureRecognizer(target: self, action: #selector(handleResetZoom))
        resetZoomTap.numberOfTapsRequired = 2
        resetZoomTap.numberOfTouchesRequired = 2

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.4
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.delegate = self

        // Tap waits for pan/longPress to fail (prevents click-on-drag).
        tap.require(toFail: pan)
        tap.require(toFail: longPress)
        tap.require(toFail: doubleTap)
        twoFingerTap.require(toFail: resetZoomTap)
        twoFingerTap.require(toFail: scroll)

        for g in [tap, doubleTap, twoFingerTap, resetZoomTap,
                  pan, longPress, scroll, pinch] as [UIGestureRecognizer] {
            view.addGestureRecognizer(g)
        }
        Log.input.info("Gestures attached — view: \(Int(view.bounds.width))x\(Int(view.bounds.height))")
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Allow pinch + two-finger scroll simultaneously.
        let isPinch = g is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
        let isPan = g is UIPanGestureRecognizer || other is UIPanGestureRecognizer
        return isPinch && isPan
    }

    // MARK: - Zoom (applied to CALayer, not UIView.transform)

    private func applyZoom() {
        guard let view = targetView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Scale from the center of the view, then translate for pan.
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, panOffset.x, panOffset.y, 0)
        t = CATransform3DScale(t, zoomScale, zoomScale, 1)
        view.displayLayer.transform = t
        CATransaction.commit()
    }

    private func resetZoomAnimated() {
        zoomScale = 1.0
        panOffset = .zero
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        targetView?.displayLayer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    // MARK: - Coordinate Mapping

    /// Maps a touch point on the iPhone screen → Mac screen coordinates.
    ///
    /// When zoomed, the display layer is scaled/panned via CATransform3D.
    /// `gesture.location(in: view)` returns the touch in the VIEW's coordinate space
    /// (unaffected by layer transform). We manually inverse the zoom/pan to find
    /// the original (unzoomed) position, then map through the aspect-fit video rect.
    private func serverPoint(from gesture: UIGestureRecognizer) -> CGPoint {
        guard let view = targetView else { return .zero }
        let touch = gesture.location(in: view)

        // Inverse the zoom/pan transform.
        // Forward: displayPos = (origPos - center) * scale + center + panOffset
        // Inverse: origPos = (displayPos - center - panOffset) / scale + center
        let cx = view.bounds.midX
        let cy = view.bounds.midY
        let origX = (touch.x - cx - panOffset.x) / zoomScale + cx
        let origY = (touch.y - cy - panOffset.y) / zoomScale + cy

        // Map through the aspect-fit video rect (based on unzoomed view bounds).
        let rect = view.videoRect(forScreenWidth: serverScreenWidth, screenHeight: serverScreenHeight)
        guard rect.width > 0, rect.height > 0 else { return .zero }

        let x = (origX - rect.minX) / rect.width * serverScreenWidth
        let y = (origY - rect.minY) / rect.height * serverScreenHeight

        return CGPoint(
            x: max(0, min(serverScreenWidth, x)),
            y: max(0, min(serverScreenHeight, y))
        )
    }

    // MARK: - Tap → Click

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = serverPoint(from: g)
        Log.input.debug("TAP at (\(Int(p.x)), \(Int(p.y)))")
        onMouseEvent?(.leftDown, p)
        onMouseEvent?(.leftUp, p)
        tapFeedback.impactOccurred()
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        let p = serverPoint(from: g)
        Log.input.debug("DOUBLE TAP at (\(Int(p.x)), \(Int(p.y)))")
        onMouseEvent?(.leftDown, p)
        onMouseEvent?(.leftUp, p)
        onMouseEvent?(.leftDown, p)
        onMouseEvent?(.leftUp, p)
        tapFeedback.impactOccurred(intensity: 0.8)
    }

    @objc private func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
        let p = serverPoint(from: g)
        Log.input.debug("RIGHT CLICK at (\(Int(p.x)), \(Int(p.y)))")
        onMouseEvent?(.rightDown, p)
        onMouseEvent?(.rightUp, p)
        tapFeedback.impactOccurred()
    }

    @objc private func handleResetZoom(_ g: UITapGestureRecognizer) {
        Log.input.debug("RESET ZOOM from \(self.zoomScale)x")
        resetZoomAnimated()
        tapFeedback.impactOccurred(intensity: 0.8)
    }

    // MARK: - Drag → Cursor Move / Pan

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        if isDragging { return }

        if zoomScale > 1.01 {
            // Zoomed → pan the display layer (not the view).
            if g.state == .changed {
                let t = g.translation(in: targetView)
                panOffset.x += t.x
                panOffset.y += t.y
                g.setTranslation(.zero, in: targetView)
                applyZoom()
            }
            return
        }

        // Not zoomed → move Mac cursor.
        let p = serverPoint(from: g)
        if g.state == .began || g.state == .changed {
            onMouseEvent?(.move, p)
        }
    }

    // MARK: - Long Press → Click-and-Drag

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        let p = serverPoint(from: g)
        switch g.state {
        case .began:
            isDragging = true
            Log.input.debug("DRAG started at (\(Int(p.x)), \(Int(p.y)))")
            onMouseEvent?(.leftDown, p)
            dragFeedback.impactOccurred()
        case .changed:
            onMouseEvent?(.move, p)
        case .ended, .cancelled:
            Log.input.debug("DRAG ended at (\(Int(p.x)), \(Int(p.y)))")
            onMouseEvent?(.leftUp, p)
            isDragging = false
        default: break
        }
    }

    // MARK: - Two-Finger → Scroll

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        guard let view = targetView else { return }
        if g.state == .changed {
            let t = g.translation(in: view)
            onScrollEvent?(t.x, t.y)
            g.setTranslation(.zero, in: view)
        }
    }

    // MARK: - Pinch → Zoom

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            Log.input.debug("PINCH started at \(self.zoomScale)x")
        case .changed:
            zoomScale = max(1.0, min(5.0, zoomScale * g.scale))
            g.scale = 1.0
            if zoomScale <= 1.01 { panOffset = .zero }
            applyZoom()
        case .ended:
            Log.input.debug("PINCH ended at \(self.zoomScale)x")
            if zoomScale <= 1.01 { resetZoomAnimated() }
        default: break
        }
    }
}
