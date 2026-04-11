import UIKit

/// Attaches gesture recognizers to the video display view and translates
/// iOS touch gestures into MyRemote mouse events.
final class GestureHandler: NSObject {

    /// Called when a mouse event should be sent to the server.
    var onMouseEvent: ((MouseEventType, CGPoint) -> Void)?
    /// Called when a scroll event should be sent.
    var onScrollEvent: ((CGFloat, CGFloat) -> Void)?

    /// Server screen dimensions for coordinate mapping.
    var serverScreenWidth: CGFloat = 1920
    var serverScreenHeight: CGFloat = 1080

    /// Current client-side zoom/pan state.
    private(set) var zoomScale: CGFloat = 1.0
    private(set) var panOffset: CGPoint = .zero

    private weak var targetView: UIView?
    private var isDragging = false

    // MARK: - Setup

    func attach(to view: UIView) {
        targetView = view

        // Single tap → left click.
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(singleTap)

        // Double tap → double click.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)

        // Two-finger tap → right click.
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTap)

        // Two-finger double tap → reset zoom.
        let twoFingerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerDoubleTap))
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerDoubleTap)
        twoFingerTap.require(toFail: twoFingerDoubleTap)

        // One-finger pan → mouse move.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        // Long press + drag → click and drag.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPress)

        // Two-finger pan → scroll.
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scroll)

        // Pinch → client-side zoom.
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        view.addGestureRecognizer(pinch)
    }

    // MARK: - Coordinate Translation

    func convertToServerCoordinates(_ touchPoint: CGPoint) -> CGPoint {
        guard let view = targetView else { return touchPoint }
        let viewSize = view.bounds.size

        let adjustedX = (touchPoint.x - panOffset.x) / zoomScale
        let adjustedY = (touchPoint.y - panOffset.y) / zoomScale

        let serverX = adjustedX / viewSize.width * serverScreenWidth
        let serverY = adjustedY / viewSize.height * serverScreenHeight

        return CGPoint(
            x: max(0, min(serverScreenWidth, serverX)),
            y: max(0, min(serverScreenHeight, serverY))
        )
    }

    // MARK: - Gesture Handlers

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let point = convertToServerCoordinates(gesture.location(in: targetView))
        onMouseEvent?(.leftDown, point)
        onMouseEvent?(.leftUp, point)
        provideHapticFeedback(.light)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = convertToServerCoordinates(gesture.location(in: targetView))
        // Two rapid click pairs for double-click.
        onMouseEvent?(.leftDown, point)
        onMouseEvent?(.leftUp, point)
        onMouseEvent?(.leftDown, point)
        onMouseEvent?(.leftUp, point)
        provideHapticFeedback(.medium)
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        let point = convertToServerCoordinates(gesture.location(in: targetView))
        onMouseEvent?(.rightDown, point)
        onMouseEvent?(.rightUp, point)
        provideHapticFeedback(.light)
    }

    @objc private func handleTwoFingerDoubleTap(_ gesture: UITapGestureRecognizer) {
        // Reset zoom to fit screen.
        zoomScale = 1.0
        panOffset = .zero
        provideHapticFeedback(.medium)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = targetView else { return }

        // If zoomed in, pan the view instead of moving the cursor.
        if zoomScale > 1.0 {
            let translation = gesture.translation(in: view)
            panOffset.x += translation.x
            panOffset.y += translation.y
            gesture.setTranslation(.zero, in: view)
            return
        }

        let point = convertToServerCoordinates(gesture.location(in: view))

        switch gesture.state {
        case .began, .changed:
            onMouseEvent?(.move, point)
        default:
            break
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let view = targetView else { return }
        let point = convertToServerCoordinates(gesture.location(in: view))

        switch gesture.state {
        case .began:
            isDragging = true
            onMouseEvent?(.leftDown, point)
            provideHapticFeedback(.heavy)
        case .changed:
            onMouseEvent?(.move, point)
        case .ended, .cancelled:
            onMouseEvent?(.leftUp, point)
            isDragging = false
        default:
            break
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard let view = targetView else { return }
        let velocity = gesture.translation(in: view)

        if gesture.state == .changed {
            onScrollEvent?(velocity.x, velocity.y)
            gesture.setTranslation(.zero, in: view)
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            zoomScale *= gesture.scale
            zoomScale = max(1.0, min(5.0, zoomScale)) // Clamp 1x–5x
            gesture.scale = 1.0
        }
    }

    // MARK: - Haptics

    private func provideHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
