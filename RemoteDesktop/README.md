# RemoteDesktop (iOS) — Clean Architecture remote-control client

A SwiftUI + MVVM + Clean Architecture iOS app that controls a computer through a
Desktop Agent, reusing the **KENIOS relay** as the signaling/relay server.

## Architecture (layers)

```
App/            Entry point, app shell, DI container, config
Presentation/   SwiftUI Views + ViewModels (Login, Dashboard, Session, Settings)
Domain/         Entities, UseCases, Interfaces (Protocols) — no frameworks
Application/    Managers/Services that orchestrate use cases (Auth, Device, Session, Input, Stream, Clipboard, FileTransfer, Audio)
Infrastructure/ Networking (URLSession/WebSocket), Streaming (Packetizer/JitterBuffer/FrameQueue/ABR), Security (CryptoKit/Keychain/TLS pinning), Repositories, Storage
Platform/       iOS-native wrappers: VideoToolbox, Metal/MetalKit, AVFoundation audio, Touch/Haptics, LocalAuthentication (biometrics)
Resources/      Localizable strings, assets
Tests/          XCTest unit tests (use cases, input engine, crypto, streaming)
```

Every capability is behind a **protocol** in `Domain/Interfaces`; concrete types
live in `Infrastructure`/`Platform` and are wired by `App/DIContainer.swift`
(Dependency Inversion + Dependency Injection). ViewModels depend only on
Managers/UseCases (MVVM). Concurrency uses `async/await`, `AsyncStream` and
`actor` (FrameQueue/JitterBuffer).

## Build

```bash
brew install xcodegen        # once
cd RemoteDesktop
xcodegen                     # generates RemoteDesktop.xcodeproj
open RemoteDesktop.xcodeproj # then ⌘R in Xcode 16+ (iOS 17+)
```

Set your signing team in Xcode (Signing & Capabilities). No third-party
packages are required.

## Run

1. On the computer you want to control, run the KENIOS Desktop Agent
   (`../pc-agent/pc_remote.py`) and sign in with your KENIOS account.
2. Launch RemoteDesktop, sign in with the **same** account.
3. The device appears on the Dashboard → tap it to open the Session screen and
   control it (trackpad, keyboard, media, scroll…). The cursor is smoothed by
   `InputManager` (batched deltas), matching the app experience.

## What is real vs. scaffold (honest notes)

- **Real & working now:** OAuth/JWT-style login, Keychain token storage, Face ID/
  Touch ID gate, device discovery, session with live JPEG preview, smooth input
  (mouse/keyboard/media/scroll), AES-256-GCM crypto, streaming primitives
  (packetizer/jitter buffer/frame queue/ABR), unit tests.
- **Scaffold / plug-in points (interfaces complete, native pipeline stubbed):**
  VideoToolbox H.264/H.265/AV1 hardware decode and the Metal 60 FPS renderer
  (the relay sends JPEG preview, so these are the drop-in path for a compressed
  Desktop Agent stream); two-way audio network tap; file transfer bytes;
  image/file clipboard. Each is clearly commented where to complete it.
- A full low-latency codec pipeline requires a Desktop Agent that speaks the
  matching wire protocol; this project provides the client architecture for it.

## Swift version

`project.yml` sets `SWIFT_VERSION = 5.0` for reliable compilation. The code uses
modern concurrency and is Swift 6-ready; raise strict concurrency incrementally.
