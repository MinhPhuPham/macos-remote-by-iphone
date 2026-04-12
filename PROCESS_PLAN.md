# MyRemote — Development Process Plan

## Development Summary

7 phases completed across 7 commits. 42 files total (38 Swift + 2 Node.js + 2 docs).

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Networking & Auth | Complete |
| 2 | Screen Capture & Streaming | Complete |
| 3 | Mouse Control | Complete |
| 4 | Keyboard Input | Complete |
| 5 | Polish & Reliability | Complete |
| 6 | WAN / Cellular Support | Complete |
| 7 | Security Hardening | Complete |

---

## Phase 1 — Networking & Auth

**Goal:** Two apps that discover each other, authenticate, and maintain a secure connection.

- [x] Shared framework: `Protocol.swift`, `MessageCodec.swift`, `KeyCodeMap.swift`, `Constants.swift`
- [x] macOS: `BonjourAdvertiser` — advertise `_myremote._tcp` via NWListener
- [x] macOS: `ServerConnection` — per-client NWConnection with heartbeat
- [x] macOS: `AuthManager` — password validation, session tokens
- [x] macOS: `KeychainHelper` — secure Keychain storage, PIN generation
- [x] macOS: `TrustedDeviceStore` — persistent trusted device list
- [x] macOS: `ServerManager` — central coordinator with NSAlert confirmation dialog
- [x] iOS: `ServerBrowser` — NWBrowser for Bonjour discovery
- [x] iOS: `ClientConnection` — NWConnection + TLS
- [x] iOS: `DeviceIdentity` — persistent device UUID (Keychain-backed)
- [x] iOS: `ServerListView` — discovered servers with pull-to-refresh
- [x] iOS: `PasswordEntryView` — password input with focus management
- [x] App entry points: `MyRemoteServerApp` (MenuBarExtra), `MyRemoteClientApp`, `ContentView`

## Phase 2 — Screen Capture & Streaming

**Goal:** Live screen streaming from Mac to iPhone.

- [x] macOS: `ScreenCaptureManager` — SCStream with permission checks
- [x] macOS: `VideoEncoder` — VTCompressionSession (H.264), SPS/PPS extraction, force keyframe
- [x] iOS: `VideoDecoder` — VTDecompressionSession (thread-safe with serial queue)
- [x] iOS: `VideoDisplayView` — AVSampleBufferDisplayLayer with cached format descriptions
- [x] iOS: `SampleBufferFactory` — cached CMVideoFormatDescription per dimensions

## Phase 3 — Mouse Control

**Goal:** Full mouse control of Mac from iPhone.

- [x] iOS: `GestureHandler` — 7 gestures (tap, double-tap, two-finger tap, pan, long-press drag, scroll, pinch)
- [x] iOS: Coordinate translation (touch → server screen) with zoom/pan offset
- [x] iOS: Pre-created haptic feedback generators
- [x] iOS: Gesture conflict resolution (pan skips when long-press drag active)
- [x] macOS: `MouseInjector` — CGEvent injection (click, double-click, right-click, scroll, drag)
- [x] macOS: Coordinate validation (reject NaN, infinity, negative)

## Phase 4 — Keyboard Input

**Goal:** Full keyboard input from iPhone to Mac.

- [x] Shared: `KeyCodeMap` — full ANSI keyboard (characters, symbols, shifted, special keys, F-keys, arrows)
- [x] iOS: `ModifierKeysBar` — sticky Cmd/Opt/Ctrl/Shift toggles (44pt HIG tap targets)
- [x] iOS: `VirtualKeyboardView` — hidden UITextField with cached keyCommands
- [x] iOS: Hardware keyboard support (arrows, escape, tab via UIKeyCommand)
- [x] macOS: `KeyboardInjector` — CGEvent keyboard injection with modifier support

## Phase 5 — Polish & Reliability

**Goal:** Polished, reliable app.

- [x] macOS: `MenuBarView` — status icon, server controls, pairing code display
- [x] macOS: `SettingsView` — 3 tabs (General/Security/Devices), error surfacing
- [x] iOS: `ConnectionStatusBar` — FPS, RTT, quality indicator, connection mode
- [x] iOS: `ToolbarView` — keyboard toggle, status toggle, disconnect
- [x] iOS: `RemoteSessionView` — full pipeline (SessionPipeline @StateObject)
- [x] iOS: scenePhase handling for background/foreground
- [x] All: `os.Logger` replacing all `print()` statements

## Phase 6 — WAN / Cellular Support

**Goal:** iPhone on 4G/5G can control a Mac anywhere over the internet.

- [x] Shared: `ConnectionMode` enum with LAN/WAN presets (bitrate, heartbeat, FPS, RTT thresholds)
- [x] Shared: `PairingModels` — PairingRegistration, PairingLookupResult, PairingCodeGenerator
- [x] Protocol: New messages — `ping` (0x0C), `pong` (0x0D), `qualityUpdate` (0x0E)
- [x] macOS: `PairingCodeManager` — generate code, register with signaling server, 30s keep-alive
- [x] iOS: `NetworkQualityMonitor` — ping/pong RTT measurement, 3-level adaptive quality
- [x] iOS: `PairingCodeLookup` — HTTP lookup on signaling server
- [x] iOS: `PairingCodeView` — code entry with auto-formatting and Mac display
- [x] iOS: `ManualConnectionView` — hostname:port entry for fallback
- [x] iOS: `ClientConnection` — WAN connect(host:port:), auto-reconnect (5 retries, exponential backoff)
- [x] iOS: `ContentView` — 3-tab picker (Local WiFi / Pairing Code / Manual IP)
- [x] iOS: Client-side heartbeat at mode-appropriate intervals
- [x] Server: `SignalingServer/server.js` — Node.js HTTP, 3 endpoints, in-memory store with 90s TTL
- [x] Auth: Rate limiting by device UUID (stable across WiFi↔cellular transitions)

## Phase 7 — Security Hardening

**Goal:** Safe for internet exposure.

- [x] Dual rate limiting: failed attempts tracked by both IP (can't fake) and device UUID (stable)
- [x] IP blocking: 5 failures → blocked 5 minutes
- [x] Global lockout: 20 failures from any source in 10 min → all auth paused
- [x] Constant-time password comparison (prevents timing attacks)
- [x] Constant-time session token validation
- [x] Max frame payload size: 16 MB (prevents memory exhaustion DoS)
- [x] Max codec buffer size: 32 MB
- [x] Auth timeout: 10 seconds to authenticate or get disconnected
- [x] Signaling server: API key for registration/deletion
- [x] Signaling server: per-IP rate limiting (10 lookups/min, 3 registrations/min)
- [x] Signaling server: anti-code-squatting (can't overwrite existing code from different IP)
- [x] Signaling server: health endpoint doesn't leak pairing count

---

## SwiftUI Implementation Guidelines

Following [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) best practices.

### Correctness (verified across all views)

- [x] `@State` properties are `private`
- [x] `@Binding` only where child modifies parent state
- [x] `@StateObject` for view-owned objects; `@ObservedObject` for injected
- [x] `ForEach` uses stable identity (Identifiable with UUID/string IDs)
- [x] `@FocusState` properties are `private`
- [x] All interactive elements use `Button` with accessibility labels
- [x] No `@State` with reference types (use `@StateObject` wrapper)

### Architecture Patterns

- `MenuBarExtra` + `Settings` scene for macOS menu bar app
- `NavigationStack` with type-safe `Route` enum for iOS navigation
- `UIViewRepresentable` with `makeUIView`/`dismantleUIView` lifecycle
- `SessionPipeline` as `@StateObject` coordinator for video/gesture pipeline
- `[weak self]` / `[weak pipeline]` on all long-lived closures
- `DispatchSourceTimer` instead of `Timer.scheduledTimer` (no RunLoop dependency)
- `os.Logger` for structured logging (no `print()`)

---

## Testing Checklist

### Authentication
- [ ] Correct password + Allow → connected
- [ ] Correct password + Deny → rejected
- [ ] Wrong password → error shown
- [ ] 5 wrong passwords from same IP → IP blocked 5 minutes
- [ ] Attacker rotates device UUIDs → still blocked by IP
- [ ] 20 total failures → global lockout activates
- [ ] Trusted device reconnects → no confirmation dialog
- [ ] Revoked device → confirmation dialog returns
- [ ] Unauthenticated connection → kicked after 10 seconds

### Streaming
- [ ] Stream starts within 2 seconds of auth
- [ ] Text on screen is legible
- [ ] 30 fps on good LAN WiFi
- [ ] Adaptive quality reduces on high latency
- [ ] Keyframe request recovers from frame drops

### Input
- [ ] Single tap → left click
- [ ] Double tap → double click
- [ ] Two-finger tap → right click
- [ ] Pan → mouse cursor moves
- [ ] Long press + drag → click and drag
- [ ] Two-finger pan → scroll
- [ ] Keyboard types in any Mac app
- [ ] Cmd+C / Cmd+V works
- [ ] Modifier keys auto-deactivate after keypress

### WAN / Cellular
- [ ] Mac shows pairing code in menu bar
- [ ] iPhone enters code → finds Mac → connects directly
- [ ] Manual IP:port entry works
- [ ] Adaptive quality adjusts for cellular latency
- [ ] Connection drops → auto-reconnects (up to 5 retries)
- [ ] WiFi → cellular transition → reconnects
- [ ] Status bar shows RTT and quality level

### Security
- [ ] Oversized frame (>16MB) rejected
- [ ] Signaling server rejects requests without API key
- [ ] Signaling server rate limits lookups (>10/min blocked)
- [ ] Cannot overwrite existing pairing code from different IP
- [ ] Health endpoint does not reveal pairing count

---

## Commit History

| # | Hash | Description |
|---|------|-------------|
| 1 | `de9e7ea` | Add README and development process plan |
| 2 | `ae3057f` | Implement complete MyRemote project (Phases 1-5) |
| 3 | `3b1ca79` | Fix SwiftUI correctness issues per AvdLee/SwiftUI-Agent-Skill audit |
| 4 | `357e7bc` | Fix 10 critical, 29 warning, 32 suggestion issues from deep audit |
| 5 | `262dea5` | Add WAN/cellular (4G/5G) support for remote access over internet |
| 6 | `b14db40` | Add pairing code system for zero-config internet connection |
| 7 | `2cccd6a` | Security hardening for internet exposure (5 critical fixes) |
