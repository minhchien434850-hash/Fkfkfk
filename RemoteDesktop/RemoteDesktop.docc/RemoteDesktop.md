# ``RemoteDesktop``

A Clean-Architecture SwiftUI client that controls a computer through a Desktop
Agent, reusing the KENIOS relay for signaling.

## Overview

RemoteDesktop is organized into strict layers with dependency inversion:

- **Presentation** — SwiftUI Views + ViewModels (MVVM).
- **Application** — Managers that orchestrate use cases (Auth, Device, Session,
  Input, Stream, Redirection, Media).
- **Domain** — Entities, UseCases and Interfaces (protocols), framework-free.
- **Infrastructure** — Networking (URLSession/WebSocket/QUIC/TLS 1.3), Security
  (CryptoKit AES-256-GCM, RSA-4096, Secure Enclave, Keychain, TLS pinning),
  Streaming (Packetizer, JitterBuffer, FrameQueue, AdaptiveBitrate),
  Monitoring, Repositories, Storage, Files.
- **Platform** — VideoToolbox, Metal, AVFoundation, GameController, Pencil,
  Haptics, LocalAuthentication.
- **Shared** — logging, retry policy, extensions.

## Topics

### Getting started
- ``AppConfig``
- ``DIContainer``

### Domain
- ``RemoteInput``
- ``Device``
- ``RemoteSession``

### Streaming
- ``AdaptiveBitrate``
- ``FrameQueue``
- ``JitterBuffer``

### Security
- ``CryptoService``
- ``RSAKeyService``
- ``SecureEnclaveService``
