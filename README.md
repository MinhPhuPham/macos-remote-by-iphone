# MyRemote — Control macOS from iPhone over WiFi

A personal two-app system that lets you view your Mac's screen on your iPhone and control it with touch gestures and keyboard input — all over local WiFi.

## Apps

| App | Platform | Role |
|-----|----------|------|
| **MyRemote Server** | macOS 14+ | Captures screen, streams video, receives and injects mouse/keyboard input |
| **MyRemote Client** | iOS 17+ | Discovers server, displays stream, sends touch and keyboard events |

## Key Features

- **Live Screen Streaming** — H.264 encoded video at up to 30 fps via ScreenCaptureKit and VideoToolbox
- **Full Mouse Control** — Tap, double-tap, right-click, drag, scroll, and pinch-to-zoom mapped from iOS gestures
- **Keyboard Input** — Virtual keyboard with sticky modifier keys (Cmd/Opt/Ctrl/Shift) and shortcut support
- **Secure Authentication** — PIN/password auth, TLS 1.3 encryption, user confirmation dialog, trusted device management
- **Automatic Discovery** — Bonjour/mDNS finds your Mac on the local network instantly
- **Adaptive Quality** — Bitrate and frame rate adjust automatically based on network conditions
- **Menu Bar App** — Server runs unobtrusively in the macOS menu bar

## Architecture

```
┌──────────────────────┐         WiFi (TLS 1.3)         ┌──────────────────────┐
│    macOS Server      │ <─────────────────────────────> │    iOS Client        │
│                      │                                 │                      │
│  ScreenCaptureKit    │ ── H.264 Video Frames ───────>  │  VideoToolbox        │
│  VideoToolbox        │                                 │  AVSampleBuffer      │
│                      │                                 │  DisplayLayer        │
│  CGEvent Injection   │ <── Mouse/Key/Scroll Events ──  │                      │
│  (Mouse + Keyboard)  │                                 │  Gesture Recognizers │
│                      │                                 │  Virtual Keyboard    │
│  NWListener          │ <── Bonjour Discovery ────────  │  NWBrowser           │
│  (Bonjour + TLS)     │                                 │  NWConnection        │
└──────────────────────┘                                 └──────────────────────┘
```

Both apps share a `MyRemoteShared` framework containing the binary protocol definitions, message codec, and key code mappings.

## Security Model

### Authentication Flow

1. **Discovery** — iOS client finds the Mac via Bonjour (`_myremote._tcp`)
2. **TLS Connection** — Encrypted TCP connection established (self-signed cert, pinned on first use)
3. **Password Auth** — Client sends PIN or password over the encrypted channel
4. **User Confirmation** — macOS server shows a native dialog:
   - **Deny** — Reject the connection
   - **Allow Once** — Grant access for this session only
   - **Always Allow** — Save device as trusted (skips dialog on future connects, still requires password)
5. **Session Token** — On success, server issues a 256-bit session token for subsequent messages

### Security Details

| Aspect | Implementation |
|--------|----------------|
| Transport | TLS 1.3 over TCP (self-signed cert, pinned on first connection) |
| Password storage | macOS Keychain (`kSecClassGenericPassword`) |
| Brute force protection | 5 failed attempts from same IP → blocked for 5 minutes |
| Session timeout | Auto-disconnect after 30 minutes of no input activity |

## Message Protocol

Custom binary protocol over a single TLS-encrypted TCP connection.

### Frame Format

```
┌─────────┬────────────┬─────────────────┐
│  Type   │  Length     │  Payload        │
│ 1 byte  │  4 bytes   │  variable       │
│         │  (UInt32)  │                 │
└─────────┴────────────┴─────────────────┘
```

### Message Types

| Type | Name | Direction | Payload |
|------|------|-----------|---------|
| `0x01` | `AUTH_REQUEST` | Client → Server | JSON: `{ password, deviceUUID, deviceName }` |
| `0x02` | `AUTH_RESULT` | Server → Client | JSON: `{ success, sessionToken?, reason? }` |
| `0x03` | `VIDEO_CONFIG` | Server → Client | H.264 SPS/PPS parameters |
| `0x04` | `VIDEO_FRAME` | Server → Client | H.264 NAL unit + timestamp |
| `0x05` | `MOUSE_EVENT` | Client → Server | JSON: `{ sessionToken, type, x, y, button? }` |
| `0x06` | `KEY_EVENT` | Client → Server | JSON: `{ sessionToken, keyCode, isDown, modifiers }` |
| `0x07` | `SCROLL_EVENT` | Client → Server | JSON: `{ sessionToken, deltaX, deltaY }` |
| `0x08` | `HEARTBEAT` | Both | Empty (keepalive every 5 seconds) |
| `0x09` | `DISCONNECT` | Both | Empty |
| `0x0A` | `KEYFRAME_REQUEST` | Client → Server | Empty (request a new IDR frame) |
| `0x0B` | `CONFIG_UPDATE` | Server → Client | JSON: `{ screenWidth, screenHeight, fps }` |

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI Framework | **SwiftUI** (both apps) |
| Screen Capture | ScreenCaptureKit (`SCStream`) |
| Video Encoding | VideoToolbox (`VTCompressionSession`, H.264) |
| Video Decoding | VideoToolbox (`VTDecompressionSession`) |
| Video Display | `AVSampleBufferDisplayLayer` |
| Networking | Network.framework (`NWListener`, `NWConnection`, `NWBrowser`) |
| Service Discovery | Bonjour / mDNS (`_myremote._tcp`) |
| Input Injection | `CGEvent` (mouse and keyboard) |
| Secure Storage | macOS Keychain |
| Encryption | TLS 1.3 (via Network.framework) |

## SwiftUI Best Practices

This project follows the [SwiftUI Expert Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) guidelines:

### State Management

- `@State` properties are always `private`
- `@StateObject` for view-owned objects (e.g., `ScreenCaptureManager`, `ServerConnection`)
- `@ObservedObject` for injected dependencies
- iOS 17+: prefer `@Observable` macro with `@State`; use `@Bindable` for injected observables needing bindings
- Separate business logic from views for testability

### View Composition

- Extract complex view bodies into focused subviews early
- Use `@ViewBuilder` for conditional content
- `ForEach` always uses stable identity (device UUIDs, not indices)
- Constant number of views per `ForEach` element

### macOS Patterns

- `MenuBarExtra` for the menu bar app (server)
- `Settings` scene for the preferences window
- `Commands` for menu bar customization
- Proper window sizing and toolbar styling

### Performance

- Minimize unnecessary state updates in hot paths (frame rendering, input handling)
- Use `.animation(_:value:)` with explicit `value` parameter
- Profile with `Self._printChanges()` during development

### Accessibility

- VoiceOver labels on all interactive elements
- Dynamic Type support throughout
- Accessibility grouping for related controls (modifier keys bar)

### Version Gating

- `#available` checks with sensible fallbacks for platform-specific APIs
- Graceful degradation on older OS versions

## macOS Permissions

The server app requires these permissions (checked and prompted on first launch):

| Permission | Why | Check |
|------------|-----|-------|
| **Screen Recording** | ScreenCaptureKit | `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` |
| **Accessibility** | CGEvent input injection | `AXIsProcessTrusted()` with options prompt |
| **Local Network** | Bonjour + TCP connections | Automatic prompt on first network use |

## Project Setup

### Xcode Workspace

**Workspace:** `MyRemote.xcworkspace`

| Target | Platform | Bundle ID |
|--------|----------|-----------|
| MyRemoteServer | macOS 14+ | `com.yourname.myremote.server` |
| MyRemoteClient | iOS 17+ | `com.yourname.myremote.client` |
| MyRemoteShared | Framework (both) | `com.yourname.myremote.shared` |

### Entitlements (macOS Server)

```xml
<key>com.apple.security.app-sandbox</key>    <false/>
<key>com.apple.security.network.server</key> <true/>
<key>com.apple.security.network.client</key> <true/>
```

### Info.plist (iOS Client)

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>MyRemote needs local network access to find and connect to your Mac.</string>
<key>NSBonjourServices</key>
<array><string>_myremote._tcp</string></array>
```

## Performance Targets

| Metric | Target | Approach |
|--------|--------|----------|
| Latency (input → display) | < 100ms | Hardware encoding, direct TCP send, no buffering |
| Frame rate | 30 fps | ScreenCaptureKit minimum interval 33ms |
| Bandwidth | 4-8 Mbps | H.264 Main profile, adaptive bitrate |
| Connection time | < 3 seconds | Bonjour discovery + TLS handshake |

## Future Enhancements

- **Clipboard sync** — Share clipboard between Mac and iPhone
- **File transfer** — Drag files between devices
- **Audio streaming** — Forward Mac audio via ScreenCaptureKit audio capture
- **Multi-display support** — Choose which display to stream
- **Remote access over internet** — Relay server or Tailscale/WireGuard for WAN access
- **Touch Bar emulation** — Virtual Touch Bar for supported MacBook Pro models

## License

Personal use project.
