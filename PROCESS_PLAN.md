# MyRemote — Development Process Plan

This document outlines the phased development plan, project structure, implementation guidelines, and testing strategy for the MyRemote app system.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [SwiftUI Implementation Guidelines](#swiftui-implementation-guidelines)
3. [Development Phases](#development-phases)
4. [Testing Checklist](#testing-checklist)

---

## Project Structure

### macOS Server

```
MacServer/
├── App/
│   ├── MyRemoteServerApp.swift        # SwiftUI app entry point (MenuBarExtra)
│   ├── MenuBarView.swift              # Menu bar icon with status
│   └── SettingsView.swift             # Password, trusted devices, preferences
├── Auth/
│   ├── AuthManager.swift              # Password validation, session tokens
│   ├── KeychainHelper.swift           # Secure password storage
│   └── TrustedDeviceStore.swift       # Trusted device list (UserDefaults/JSON)
├── Network/
│   ├── BonjourAdvertiser.swift        # NWListener with Bonjour service
│   ├── ServerConnection.swift         # NWConnection manager per client
│   └── MessageCodec.swift             # Encode/decode binary protocol
├── Capture/
│   ├── ScreenCaptureManager.swift     # ScreenCaptureKit setup & delegate
│   └── VideoEncoder.swift             # VTCompressionSession (H.264)
├── Input/
│   ├── MouseInjector.swift            # CGEvent mouse injection
│   └── KeyboardInjector.swift         # CGEvent keyboard injection
└── Shared/
    ├── Protocol.swift                 # Message type definitions
    ├── KeyCodeMap.swift               # Character → macOS virtual key codes
    └── Constants.swift                # Ports, timeouts, etc.
```

### iOS Client

```
iOSClient/
├── App/
│   ├── MyRemoteClientApp.swift        # SwiftUI app entry
│   └── ContentView.swift              # Navigation: discovery → connect → remote
├── Auth/
│   ├── PasswordEntryView.swift        # Password input screen
│   └── DeviceIdentity.swift           # Generate/store device UUID
├── Network/
│   ├── ServerBrowser.swift            # NWBrowser for Bonjour discovery
│   ├── ClientConnection.swift         # NWConnection + TLS
│   └── MessageCodec.swift             # Shared protocol codec
├── Video/
│   ├── VideoDecoder.swift             # VTDecompressionSession
│   └── VideoDisplayView.swift         # AVSampleBufferDisplayLayer in UIView
├── Input/
│   ├── GestureHandler.swift           # All gesture recognizers
│   ├── VirtualKeyboardView.swift      # Keyboard toggle + capture
│   └── ModifierKeysBar.swift          # Cmd/Opt/Ctrl/Shift toggle buttons
├── Views/
│   ├── ServerListView.swift           # List of discovered servers
│   ├── RemoteSessionView.swift        # Full screen remote view
│   ├── ConnectionStatusBar.swift      # FPS, latency, status overlay
│   └── ToolbarView.swift              # Keyboard button, disconnect, etc.
└── Shared/
    ├── Protocol.swift
    ├── KeyCodeMap.swift
    └── Constants.swift
```

### Shared Framework

```
MyRemoteShared/
├── Protocol.swift                     # MessageType enum + ProtocolFrame
├── MessageCodec.swift                 # Encode/decode binary frames
├── KeyCodeMap.swift                   # Character → macOS virtual key codes
└── Constants.swift                    # Ports, timeouts, service type
```

---

## SwiftUI Implementation Guidelines

Following the [SwiftUI Expert Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) best practices.

### Correctness Checklist

These are hard rules — violations are always bugs:

- [ ] `@State` properties are `private`
- [ ] `@Binding` only where a child modifies parent state
- [ ] Passed values never declared as `@State` or `@StateObject` (they ignore updates)
- [ ] `@StateObject` for view-owned objects; `@ObservedObject` for injected
- [ ] iOS 17+: `@State` with `@Observable`; `@Bindable` for injected observables needing bindings
- [ ] `ForEach` uses stable identity (never `.indices` for dynamic content)
- [ ] Constant number of views per `ForEach` element
- [ ] `.animation(_:value:)` always includes the `value` parameter
- [ ] `@FocusState` properties are `private`
- [ ] `#available` gating with sensible fallbacks for version-specific APIs

### State Management Rules

| Scenario | Wrapper | Example |
|----------|---------|---------|
| View-owned simple value | `@State private` | `@State private var isConnected = false` |
| View-owned reference type | `@StateObject` | `@StateObject private var captureManager = ScreenCaptureManager()` |
| Injected reference type | `@ObservedObject` | `@ObservedObject var connection: ServerConnection` |
| iOS 17+ observable | `@State` + `@Observable` | `@State private var authManager = AuthManager()` |
| Injected observable needing bindings | `@Bindable` | `@Bindable var settings: SettingsModel` |
| Two-way binding to parent | `@Binding` | `@Binding var password: String` |
| Focus tracking | `@FocusState private` | `@FocusState private var isKeyboardFocused: Bool` |

### View Composition Patterns

- **Extract early**: If a view body exceeds ~30 lines, extract subviews
- **Business logic separation**: Managers and services are separate classes, not embedded in views
- **`@ViewBuilder`**: Use for conditional content in container views
- **Stable identity**: `ForEach` over collections with `Identifiable` conformance (device UUID, server ID)

### macOS-Specific Patterns

```swift
// Menu bar app using MenuBarExtra
@main
struct MyRemoteServerApp: App {
    @StateObject private var server = ServerManager()

    var body: some Scene {
        MenuBarExtra("MyRemote", systemImage: server.statusIcon) {
            MenuBarView(server: server)
        }

        Settings {
            SettingsView(server: server)
        }
    }
}
```

- Use `MenuBarExtra` for the server (no dock icon)
- Use `Settings` scene for the preferences window
- Use `Commands` for custom menu items
- Apply proper `.windowStyle()` and `.windowToolbarStyle()` modifiers

### iOS-Specific Patterns

- Use `NavigationStack` for the server list → password → session flow
- `AVSampleBufferDisplayLayer` wrapped in `UIViewRepresentable` for video display
- Hidden `UITextField` via `UIViewRepresentable` for keyboard input capture
- Gesture recognizers attached to the video display view
- `UIImpactFeedbackGenerator` for haptic feedback on taps

### Performance Guidelines

- **Video path**: Minimize allocations in the frame decode/display pipeline — this runs at 30 fps
- **Input path**: Send events immediately, no batching or debouncing
- **State updates**: Only update `@Published`/`@State` properties that affect visible UI
- **Profiling**: Use `Self._printChanges()` during development to detect unnecessary redraws
- **Lazy loading**: Use `LazyVStack` in server list if many servers could appear

---

## Development Phases

### Phase 1 — Networking & Auth (Week 1)

**Goal:** Two apps that find each other, authenticate, and maintain a secure connection.

- [ ] Set up Xcode workspace with both targets + shared framework
- [ ] Implement `Protocol.swift` and `MessageCodec.swift` in shared framework
- [ ] macOS: `BonjourAdvertiser` — advertise `_myremote._tcp` service
- [ ] macOS: `ServerConnection` — accept TLS connections via `NWListener`
- [ ] iOS: `ServerBrowser` — discover servers via `NWBrowser`
- [ ] iOS: `ServerListView` — display found servers
- [ ] iOS: `PasswordEntryView` — password input UI
- [ ] iOS: Send `AUTH_REQUEST` with password + device UUID
- [ ] macOS: `AuthManager` — validate password from Keychain
- [ ] macOS: Show `NSAlert` confirmation dialog (Deny / Allow Once / Always Allow)
- [ ] macOS: `TrustedDeviceStore` — persist trusted device UUIDs
- [ ] macOS: Send `AUTH_RESULT` back to client
- [ ] iOS: Handle auth success (proceed) and failure (show error, retry)
- [ ] Implement brute force protection (5 attempts → 5 min block)
- [ ] Test: iPhone discovers Mac, enters password, Mac confirms, connection established

### Phase 2 — Screen Capture & Streaming (Week 2-3)

**Goal:** Live screen streaming from Mac to iPhone.

- [ ] macOS: `ScreenCaptureManager` — set up `SCStream` with half-resolution config
- [ ] macOS: `VideoEncoder` — create `VTCompressionSession` for H.264
- [ ] macOS: Extract SPS/PPS from first keyframe, send as `VIDEO_CONFIG`
- [ ] macOS: Encode each captured frame, extract NAL units, send as `VIDEO_FRAME`
- [ ] iOS: `VideoDecoder` — parse `VIDEO_CONFIG`, create `CMFormatDescription`
- [ ] iOS: Decode incoming H.264 NAL units via `VTDecompressionSession`
- [ ] iOS: `VideoDisplayView` — render decoded frames via `AVSampleBufferDisplayLayer`
- [ ] iOS: Implement `KEYFRAME_REQUEST` for recovery after frame drops
- [ ] macOS: Handle keyframe requests (force IDR frame)
- [ ] Implement heartbeat (every 5 seconds) and connection timeout (30 min idle)
- [ ] Test: Mac screen is visible on iPhone in real time

### Phase 3 — Mouse Control (Week 3-4)

**Goal:** Full mouse control of Mac from iPhone.

- [ ] iOS: `GestureHandler` — attach gesture recognizers to display view
- [ ] iOS: Implement coordinate translation (touch → server screen coordinates)
- [ ] iOS: Single tap → left click
- [ ] iOS: Double tap → double click
- [ ] iOS: Two-finger tap → right click
- [ ] iOS: One-finger pan → mouse move
- [ ] iOS: Long press + drag → click and drag
- [ ] iOS: Two-finger scroll → scroll event
- [ ] iOS: Pinch to zoom (client-side view scaling)
- [ ] iOS: Pan when zoomed in (scroll around the zoomed view)
- [ ] iOS: Double-tap with two fingers → reset zoom to fit screen
- [ ] macOS: `MouseInjector` — receive mouse events, inject via `CGEvent`
- [ ] macOS: Check Accessibility permission on launch, prompt if missing
- [ ] Test: All mouse actions work correctly from iPhone

**Gesture → Mouse Mapping:**

| iOS Gesture | Mouse Event | Details |
|-------------|-------------|---------|
| Single tap | Left click | `leftDown` + `leftUp` at touch coordinate |
| Double tap | Double click | Two click pairs rapidly |
| Two-finger tap | Right click | `rightDown` + `rightUp` |
| One-finger pan | Mouse move | Translate touch delta to screen coordinates |
| Long press + drag | Click and drag | `leftDown` → `move` events → `leftUp` on release |
| Two-finger scroll | Scroll wheel | `SCROLL_EVENT` with deltaX/deltaY |
| Pinch | Zoom (client only) | Scale display layer, adjust coordinate mapping |

### Phase 4 — Keyboard Input (Week 4-5)

**Goal:** Full keyboard input from iPhone to Mac.

- [ ] Shared: Complete `KeyCodeMap.swift` — full ANSI keyboard mapping
- [ ] iOS: `ModifierKeysBar` — Cmd/Opt/Ctrl/Shift toggle buttons (sticky behavior)
- [ ] iOS: `VirtualKeyboardView` — hidden `UITextField` to invoke iOS keyboard
- [ ] iOS: Capture keystrokes, map to key codes, send `KEY_EVENT`
- [ ] iOS: Support special keys: arrows, escape, tab, delete, return
- [ ] iOS: Support common shortcuts (Cmd+C, Cmd+V, Cmd+Z, Cmd+A, Cmd+Tab)
- [ ] macOS: `KeyboardInjector` — receive key events, inject via `CGEvent` with modifiers
- [ ] Test: Type on iPhone keyboard → text appears in any Mac app

### Phase 5 — Polish & Reliability (Week 5-6)

**Goal:** Polished, reliable app ready for daily personal use.

- [ ] macOS: Menu bar app UI (status icon, start/stop, settings)
- [ ] macOS: Settings window (password change, trusted devices, stream quality)
- [ ] iOS: `ConnectionStatusBar` — show FPS, latency, connection status overlay
- [ ] iOS: `ToolbarView` — keyboard toggle, disconnect button, settings
- [ ] Implement adaptive bitrate (adjust based on measured RTT)
- [ ] Implement auto-reconnect on connection drop (with exponential backoff)
- [ ] iOS: Stop stream when app goes to background, resume on foreground
- [ ] iOS: Haptic feedback on tap gestures (`UIImpactFeedbackGenerator`)
- [ ] macOS: Session timeout (auto-disconnect after 30 min idle)
- [ ] macOS: Handle multiple connection attempts (reject while one client is active)
- [ ] Test edge cases: WiFi drop, sleep/wake, permission revocation
- [ ] Performance profiling: ensure < 100ms input latency

---

## Testing Checklist

### Authentication Tests

- [ ] Correct password + Allow → connection succeeds
- [ ] Correct password + Deny → connection rejected, client shows error
- [ ] Wrong password → client shows "Invalid password"
- [ ] 5 wrong passwords → client blocked for 5 minutes
- [ ] Trusted device reconnects → no confirmation dialog, just password
- [ ] Revoked device reconnects → confirmation dialog reappears
- [ ] Server closed during "waiting for approval" → client handles gracefully

### Streaming Tests

- [ ] Stream starts within 2 seconds of auth
- [ ] Image quality is readable (text on screen is legible)
- [ ] Frame rate stays at ~30 fps on good WiFi
- [ ] Adaptive quality kicks in on slow network
- [ ] Stream recovers after brief WiFi interruption

### Input Tests

- [ ] Click opens apps, selects text, presses buttons
- [ ] Drag works for moving windows, selecting text ranges
- [ ] Right-click opens context menus
- [ ] Scroll works in browsers, documents, lists
- [ ] Keyboard types correctly in TextEdit, Terminal, browser
- [ ] Cmd+C / Cmd+V copies and pastes
- [ ] Cmd+Tab switches apps
- [ ] Escape closes dialogs

### Performance Tests

- [ ] Input-to-display latency < 100ms on local WiFi
- [ ] Consistent 30 fps with no dropped frames on 5 GHz WiFi
- [ ] Memory usage stable over 30+ minute sessions
- [ ] CPU usage reasonable on both devices during streaming
- [ ] Adaptive quality transitions smoothly without visual glitches

---

## Key Implementation References

### Screen Capture Setup

```swift
let content = try await SCShareableContent.current
let display = content.displays.first!
let config = SCStreamConfiguration()
config.width = display.width / 2
config.height = display.height / 2
config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
config.pixelFormat = kCVPixelFormatType_32BGRA
config.showsCursor = true

let filter = SCContentFilter(display: display, excludingWindows: [])
let stream = SCStream(filter: filter, configuration: config, delegate: self)
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
try await stream.startCapture()
```

### Video Encoding Configuration

```swift
VTSessionSetProperty(session!, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
VTSessionSetProperty(session!, key: kVTCompressionPropertyKey_ProfileLevel,
                     value: kVTProfileLevel_H264_Main_AutoLevel)
VTSessionSetProperty(session!, key: kVTCompressionPropertyKey_AverageBitRate,
                     value: 4_000_000 as CFNumber)
VTSessionSetProperty(session!, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                     value: 60 as CFNumber)
```

### Coordinate Translation (iOS)

```swift
func convertToServerCoordinates(touchPoint: CGPoint) -> CGPoint {
    let viewSize = displayView.bounds.size
    let serverSize = CGSize(width: serverScreenWidth, height: serverScreenHeight)
    let adjustedX = (touchPoint.x - panOffsetX) / zoomScale
    let adjustedY = (touchPoint.y - panOffsetY) / zoomScale
    let serverX = adjustedX / viewSize.width * serverSize.width
    let serverY = adjustedY / viewSize.height * serverSize.height
    return CGPoint(x: serverX, y: serverY)
}
```

### Adaptive Quality

```swift
if averageRTT > 100 {
    encoder.setBitrate(2_000_000)
    encoder.setFrameRate(15)
} else if averageRTT < 50 {
    encoder.setBitrate(6_000_000)
    encoder.setFrameRate(30)
}
```

### Bonjour Service

- Service type: `_myremote._tcp`
- Default port: `5900` (configurable)
- TXT record: `{ "version": "1.0", "hostname": "MacBook-Pro" }`
