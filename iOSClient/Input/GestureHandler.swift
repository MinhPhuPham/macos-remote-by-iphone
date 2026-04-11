import UIKit

/// Attaches gesture recognizers to the video display view and translates
/// iOS touch gestures into MyRemote mouse events.
final class GestureHandler: NSObject {

    var onMouseEvent: ((MouseEventType, CGPoint) -> Void)?
    var onScrollEvent: ((CGFloat, CGFloat) -> Void)?

    var serverScreenWidth: CGFloat = 1920
    var serverScreenHeight: CGFloat = 1080

    private(set) var zoomScale: CGFloat = 1.0
    private(set) var panOffset: CGPoint = .zero

    private weak var targetView: UIView?
    private var isDragging = false
    private var isAttached = false

    // Pre-created haptic generators for performance.
    private let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private let mediumFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let heavyFeedback = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Setup

    func attach(to view: UIView) {
        // Remove existing recognizers to prevent duplicates on re-attach.
        if let existingView = targetView {
            existingView.gestureRecognizers?.forEach { existingView.removeGestureRecognizer($0) }
        }

        targetView = view
        isAttached = true

        // Prepare haptic engines.
        lightFeedback.prepare()
        mediumFeedback.prepare()
        heavyFeedback.prepare()

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(singleTap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTap)

        let twoFingerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerDoubleTap))
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerDoubleTap)
        twoFingerTap.require(toFail: twoFingerDoubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPress)

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scroll)

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
        lightFeedback.impactOccurred()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = convertToServerCoordinates(gesture.location(in: targetView))
        onMouseEvent?(.leftDown, point)
        onMouseEvent?(.leftUp, point)
        onMouseEvent?(.leftDown, point)
        onMouseEvent?(.leftUp, point)
        mediumFeedback.impactOccurred()
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        let point = convertToServerCoordinates(gesture.location(in: targetView))
        onMouseEvent?(.rightDown, point)
        onMouseEvent?(.rightUp, point)
        lightFeedback.impactOccurred()
    }

    @objc private func handleTwoFingerDoubleTap(_ gesture: UITapGestureRecognizer) {
        zoomScale = 1.0
        panOffset = .zero
        mediumFeedback.impactOccurred()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = targetView else { return }

        // Skip if long-press drag is active to avoid conflicting events.
        if isDragging { return }

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
            heavyFeedback.impactOccurred()
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
            zoomScale = max(1.0, min(5.0, zoomScale))
            gesture.scale = 1.0
        }
    }
}
