# MyRemote — Control macOS from iPhone over Any Network

A personal two-app system that lets you view your Mac's screen on your iPhone and control it with touch gestures and keyboard input — over local WiFi or the internet (4G/5G).

## Features

- **Live Screen Streaming** — H.264 hardware encoding at up to 30fps via ScreenCaptureKit + VideoToolbox
- **Full Mouse Control** — Tap, double-tap, right-click, drag, scroll, pinch-to-zoom from iOS gestures
- **Keyboard Input** — Virtual keyboard with sticky modifier keys (Cmd/Opt/Ctrl/Shift) and shortcut support
- **3 Connection Modes** — Local WiFi (Bonjour auto-discovery), Pairing Code (internet via signaling server), Manual IP
- **Adaptive Quality** — Real-time RTT measurement with automatic bitrate/FPS adjustment per network conditions
- **Auto-Reconnect** — Exponential backoff retry on transient network failures (cellular handoffs, brief drops)
- **Secure Authentication** — TLS 1.3, password auth, user confirmation dialog, dual rate limiting, session tokens
- **Menu Bar App** — macOS server runs unobtrusively with status icon and pairing code display

## Architecture

```
┌──────────────┐                                    ┌──────────────┐
│  iOS Client  │                                    │ macOS Server │
│              │     Direct P2P (TLS 1.3 TCP)       │              │
│ Touch Input ─┼───────────────────────────────────>│─ CGEvent     │
│              │                                    │  Injection   │
│ Video Display│<───────────────────────────────────┼─ H.264 Stream│
│              │                                    │  (SCStream)  │
└──────┬───────┘                                    └──────┬───────┘
       │                                                   │
       │  ┌─────────────────────────┐                      │
       └──┤  Signaling Server       ├──────────────────────┘
          │  (code → IP lookup only)│
          │  No video/input traffic │
          └─────────────────────────┘
```

All video streaming and input control flows **directly between devices** (P2P). The signaling server is only used for pairing code lookup — it never sees any traffic.

## Connection Modes

| Mode | Use Case | How It Works |
|------|----------|-------------|
| **Local WiFi** | Same network | Bonjour auto-discovers your Mac |
| **Pairing Code** | Any network (4G/5G) | Mac shows 6-char code → iPhone looks it up → direct P2P |
| **Manual IP** | Fallback | Enter hostname:port manually |

### Pairing Code Flow

```
Mac starts → generates code "HK4-M7N" → registers with signaling server
iPhone user enters "HK4M7N" → server returns Mac's IP:port → direct connection
```

## Security Model

### Authentication Flow

1. **TLS 1.3** — Encrypted TCP connection (self-signed certificate)
2. **Password Auth** — Client sends PIN/password over TLS
3. **User Confirmation** — Mac shows native dialog: Deny / Allow Once / Always Allow
4. **Session Token** — 256-bit cryptographic token for all subsequent messages

### Protection Layers

| Layer | What It Does |
|-------|-------------|
| **TLS 1.3** | All traffic encrypted |
| **Auth Timeout** | Unauthenticated connections kicked after 10 seconds |
| **Dual Rate Limiting** | Failed attempts tracked by both IP and device UUID |
| **IP Blocking** | 5 failures from same IP → blocked 5 minutes |
| **Global Lockout** | 20 failures from any source in 10 min → server pauses all auth |
| **Constant-Time Compare** | Password and token comparison resistant to timing attacks |
| **Frame Size Limit** | Max 16MB payload, 32MB buffer (prevents memory DoS) |
| **Session Tokens** | 256-bit random, validated on every input event |
| **Signaling API Key** | Registration/deletion requires secret key |
| **Signaling Rate Limit** | 10 lookups/min, 3 registrations/min per IP |

### Trusted Devices

Devices approved with "Always Allow" skip the confirmation dialog on reconnection (password still required). Manage trusted devices in Settings → Devices → Revoke.

## Message Protocol

Custom binary protocol over TLS-encrypted TCP.

### Frame Format

```
┌─────────┬────────────┬─────────────────┐
│  Type   │  Length     │  Payload        │
│ 1 byte  │  4 bytes   │  variable       │
│         │  (UInt32)  │  (max 16 MB)    │
└─────────┴────────────┴─────────────────┘
```

### Message Types

| Type | Name | Direction | Purpose |
|------|------|-----------|---------|
| `0x01` | AUTH_REQUEST | Client → Server | Password + device UUID |
| `0x02` | AUTH_RESULT | Server → Client | Success/failure + session token |
| `0x03` | VIDEO_CONFIG | Server → Client | H.264 SPS/PPS parameters |
| `0x04` | VIDEO_FRAME | Server → Client | H.264 NAL unit |
| `0x05` | MOUSE_EVENT | Client → Server | Click, move, drag coordinates |
| `0x06` | KEY_EVENT | Client → Server | Key code + modifiers |
| `0x07` | SCROLL_EVENT | Client → Server | Scroll delta X/Y |
| `0x08` | HEARTBEAT | Both | Keepalive |
| `0x09` | DISCONNECT | Both | Graceful close |
| `0x0A` | KEYFRAME_REQ | Client → Server | Request IDR frame |
| `0x0B` | CONFIG_UPDATE | Server → Client | Screen dimensions + FPS |
| `0x0C` | PING | Client → Server | RTT measurement |
| `0x0D` | PONG | Server → Client | RTT response |
| `0x0E` | QUALITY_UPDATE | Client → Server | Request bitrate/FPS change |

## Adaptive Quality

The client continuously measures round-trip time via ping/pong and adjusts quality:

| Quality | LAN Threshold | WAN Threshold | Bitrate | FPS |
|---------|--------------|---------------|---------|-----|
| **Good** | < 50ms | < 100ms | 6 / 3 Mbps | 30 / 24 |
| **Fair** | 50-100ms | 100-250ms | 4 / 1.5 Mbps | 30 / 24 |
| **Poor** | > 100ms | > 250ms | 2 / 0.5 Mbps | 15 / 10 |

Status bar shows real-time FPS, RTT latency, and quality level indicator.

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI Framework | SwiftUI (both apps) |
| Screen Capture | ScreenCaptureKit (`SCStream`) |
| Video Encoding | VideoToolbox (`VTCompressionSession`, H.264) |
| Video Decoding | VideoToolbox (`VTDecompressionSession`) |
| Video Display | `AVSampleBufferDisplayLayer` |
| Networking | Network.framework (`NWListener`, `NWConnection`, `NWBrowser`) |
| Discovery | Bonjour / mDNS (`_myremote._tcp`) |
| Input Injection | `CGEvent` (mouse + keyboard) |
| Secure Storage | macOS Keychain + iOS Keychain |
| Encryption | TLS 1.3 (Network.framework) |
| Signaling Server | Node.js (zero dependencies) |
| Logging | `os.Logger` (structured, level-based) |

## Project Structure

```
MyRemoteShared/Sources/         Shared framework (both platforms)
├── Protocol.swift              Message types, frame codec, payload structs
├── MessageCodec.swift          Thread-safe streaming decoder
├── Constants.swift             LAN/WAN presets, ConnectionMode enum
├── KeyCodeMap.swift            Full ANSI keyboard mapping
└── PairingModels.swift         Pairing code generation/lookup types

MacServer/                      macOS server app
├── App/
│   ├── MyRemoteServerApp.swift MenuBarExtra entry point
│   ├── ServerManager.swift     Central coordinator (auth, input, streaming)
│   ├── MenuBarView.swift       Menu bar UI + pairing code display
│   └── SettingsView.swift      Password, devices, quality, permissions
├── Auth/
│   ├── AuthManager.swift       Dual rate limiting, constant-time compare
│   ├── KeychainHelper.swift    Secure storage, token generation
│   └── TrustedDeviceStore.swift Persistent trusted device list
├── Network/
│   ├── BonjourAdvertiser.swift NWListener + Bonjour + TLS
│   ├── ServerConnection.swift  Per-client connection + auth timeout
│   └── PairingCodeManager.swift Signaling server registration
├── Capture/
│   ├── ScreenCaptureManager.swift SCStream with permission checks
│   └── VideoEncoder.swift      H.264 encoding + force keyframe
└── Input/
    ├── MouseInjector.swift     CGEvent mouse/scroll injection
    └── KeyboardInjector.swift  CGEvent keyboard injection

iOSClient/                      iOS client app
├── App/
│   ├── MyRemoteClientApp.swift Entry point + scenePhase handling
│   └── ContentView.swift       3-tab navigation (WiFi/Code/Manual)
├── Auth/
│   ├── PasswordEntryView.swift Password input UI
│   └── DeviceIdentity.swift    Device UUID (Keychain-backed)
├── Network/
│   ├── ServerBrowser.swift     Bonjour discovery
│   ├── ClientConnection.swift  TLS + reconnect + RTT + adaptive quality
│   ├── NetworkQualityMonitor.swift Ping/pong RTT + quality decisions
│   └── PairingCodeLookup.swift Signaling server code lookup
├── Video/
│   ├── VideoDecoder.swift      Thread-safe H.264 decoding
│   └── VideoDisplayView.swift  AVSampleBufferDisplayLayer + cached format
├── Input/
│   ├── GestureHandler.swift    7 gestures with pre-created haptics
│   ├── VirtualKeyboardView.swift Hidden UITextField capture
│   └── ModifierKeysBar.swift   Sticky Cmd/Opt/Ctrl/Shift toggles
└── Views/
    ├── ServerListView.swift    Bonjour server list + pull-to-refresh
    ├── RemoteSessionView.swift Full-screen session (video + input + toolbar)
    ├── PairingCodeView.swift   6-char code entry + lookup
    ├── ManualConnectionView.swift Manual host:port entry
    ├── ConnectionStatusBar.swift FPS + RTT + quality overlay
    └── ToolbarView.swift       Keyboard toggle + disconnect

SignalingServer/                Lightweight pairing code server
├── server.js                  Node.js HTTP (rate limit, API key, anti-squat)
└── package.json               Zero dependencies, Node.js 18+
```

**38 Swift files** + **2 server files** + **2 documentation files** = **42 files total**

## Setup Guide

### 1. Xcode Workspace

| Target | Platform | Bundle ID |
|--------|----------|-----------|
| MyRemoteServer | macOS 14+ | `com.yourname.myremote.server` |
| MyRemoteClient | iOS 17+ | `com.yourname.myremote.client` |
| MyRemoteShared | Framework | `com.yourname.myremote.shared` |

### 2. macOS Permissions (prompted on first launch)

| Permission | Why | Check |
|------------|-----|-------|
| Screen Recording | ScreenCaptureKit | `CGPreflightScreenCaptureAccess()` |
| Accessibility | CGEvent injection | `AXIsProcessTrusted()` |
| Local Network | Bonjour + TCP | Automatic system prompt |

### 3. iOS Info.plist

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>MyRemote needs local network access to find and connect to your Mac.</string>
<key>NSBonjourServices</key>
<array><string>_myremote._tcp</string></array>
```

### 4. Signaling Server (for internet access)

```bash
cd SignalingServer
API_KEY=your-secret-key-here node server.js
```

Deploy to any VPS ($5/mo) or serverless platform. Update `signalingBaseURL` and `apiKey` in `PairingCodeManager.swift` and `PairingCodeLookup.swift`.

### 5. Port Forwarding (for internet access)

Forward TCP port **5910** on your router to your Mac's local IP. Required for iPhone to reach your Mac over the internet.

## Gesture Mapping

| iOS Gesture | Mouse Action |
|-------------|-------------|
| Single tap | Left click |
| Double tap | Double click |
| Two-finger tap | Right click |
| One-finger pan | Mouse move |
| Long press + drag | Click and drag |
| Two-finger pan | Scroll |
| Pinch | Zoom (client-side) |
| Two-finger double tap | Reset zoom |

## License

Personal use project.
