import Foundation
import ReplayKit
import AVFoundation
import UIKit

final class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()

    @Published var isRecording = false
    @Published var isStreaming = false
    @Published var error: String?
    @Published var latestFrame: CGImage?
    @Published var duration: TimeInterval = 0

    private let recorder = RPScreenRecorder.shared()
    private var streams: [RTMPClient] = []
    private var startTime: Date?
    private var durationTimer: Timer?
    private var videoEncoder: H264Encoder?
    private var audioEncoder: AACEncoder?
    private let ciContext = CIContext()

    var isAvailable: Bool { recorder.isAvailable }

    func startCapture(targets: [(rtmp: String, key: String)]) {
        guard !isRecording else { return }
        error = nil
        streams.removeAll()

        for t in targets {
            let full = t.rtmp.hasSuffix("/") ? t.rtmp + t.key : t.rtmp + "/" + t.key
            let client = RTMPClient(url: full)
            streams.append(client)
        }

        videoEncoder = H264Encoder()
        audioEncoder = AACEncoder()

        for s in streams { s.connect() }

        recorder.isMicrophoneEnabled = true
        recorder.startCapture(handler: { [weak self] sampleBuffer, type, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.error = error.localizedDescription }
                return
            }
            switch type {
            case .video:
                self.processVideo(sampleBuffer)
            case .audioApp, .audioMic:
                self.processAudio(sampleBuffer)
            @unknown default:
                break
            }
        }, completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.error = error.localizedDescription
                    self?.isRecording = false
                } else {
                    self?.isRecording = true
                    self?.isStreaming = true
                    self?.startTime = Date()
                    self?.startDurationTimer()
                }
            }
        })
    }

    func stopCapture() {
        guard isRecording else { return }
        recorder.stopCapture { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRecording = false
                self?.isStreaming = false
                self?.durationTimer?.invalidate()
                self?.durationTimer = nil
                self?.duration = 0
                self?.latestFrame = nil
            }
        }
        for s in streams { s.disconnect() }
        streams.removeAll()
        videoEncoder = nil
        audioEncoder = nil
    }

    private func processVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if Int(duration) % 2 == 0 || latestFrame == nil {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            if let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                DispatchQueue.main.async { self.latestFrame = cg }
            }
        }

        guard let encoder = videoEncoder else { return }
        let nalus = encoder.encode(pixelBuffer: pixelBuffer,
                                   pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard !nalus.isEmpty else { return }

        let ts = UInt32(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
        let flvTag = FLVPacket.videoTag(nalus: nalus, timestamp: ts, isKeyframe: encoder.lastWasKeyframe)

        for s in streams { s.send(flvTag) }
    }

    private func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let encoder = audioEncoder else { return }
        let aacData = encoder.encode(sampleBuffer: sampleBuffer)
        guard !aacData.isEmpty else { return }

        let ts = UInt32(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
        let flvTag = FLVPacket.audioTag(aacData: aacData, timestamp: ts)

        for s in streams { s.send(flvTag) }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            self.duration = Date().timeIntervalSince(start)
        }
    }
}

// MARK: - H264 Software Encoder (VideoToolbox)
import VideoToolbox

final class H264Encoder {
    private var session: VTCompressionSession?
    private(set) var lastWasKeyframe = false
    private var sps: Data?
    private var pps: Data?
    private var pendingNALUs: [Data] = []
    private let queue = DispatchQueue(label: "h264.encode")

    init() {}

    func encode(pixelBuffer: CVPixelBuffer, pts: CMTime) -> [Data] {
        if session == nil { setupSession(width: CVPixelBufferGetWidth(pixelBuffer),
                                         height: CVPixelBufferGetHeight(pixelBuffer)) }
        guard let session else { return [] }

        pendingNALUs.removeAll()
        lastWasKeyframe = false

        var flags = VTEncodeInfoFlags()
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer,
                                        presentationTimeStamp: pts, duration: .invalid,
                                        frameProperties: nil, sourceFrameRefcon: Unmanaged.passUnretained(self).toOpaque(),
                                        infoFlagsOut: &flags)

        return pendingNALUs
    }

    private func setupSession(width: Int, height: Int) {
        let w = Int32(width)
        let h = Int32(height)

        var s: VTCompressionSession?
        let cb: VTCompressionOutputCallback = { refcon, _, status, flags, sampleBuffer in
            guard status == noErr, let sampleBuffer, let refcon else { return }
            let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
            encoder.handleOutput(sampleBuffer: sampleBuffer, flags: flags)
        }
        let status = VTCompressionSessionCreate(allocator: nil, width: w, height: h,
                                                 codecType: kCMVideoCodecType_H264,
                                                 encoderSpecification: nil,
                                                 imageBufferAttributes: nil,
                                                 compressedDataAllocator: nil,
                                                 outputCallback: cb,
                                                 refcon: Unmanaged.passUnretained(self).toOpaque(),
                                                 compressionSessionOut: &s)
        guard status == noErr, let s else { return }
        session = s

        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: NSNumber(value: 2_500_000))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: NSNumber(value: 60))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    private func handleOutput(sampleBuffer: CMSampleBuffer, flags: VTEncodeInfoFlags) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        let isKeyframe: Bool
        if let arr = attachments as? [[CFString: Any]], let first = arr.first {
            isKeyframe = !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        } else {
            isKeyframe = true
        }
        lastWasKeyframe = isKeyframe

        if isKeyframe {
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
                extractParameterSets(format)
            }
            if let s = sps { pendingNALUs.append(s) }
            if let p = pps { pendingNALUs.append(p) }
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard let dataPointer, totalLength > 0 else { return }

        var offset = 0
        while offset < totalLength - 4 {
            var naluLength: UInt32 = 0
            memcpy(&naluLength, dataPointer.advanced(by: offset), 4)
            naluLength = naluLength.bigEndian
            offset += 4
            guard naluLength > 0, offset + Int(naluLength) <= totalLength else { break }
            let nalu = Data(bytes: dataPointer.advanced(by: offset), count: Int(naluLength))
            pendingNALUs.append(nalu)
            offset += Int(naluLength)
        }
    }

    private func extractParameterSets(_ format: CMFormatDescription) {
        var spsSize = 0, spsCount = 0
        var spsPointer: UnsafePointer<UInt8>?
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0,
                                                              parameterSetPointerOut: &spsPointer,
                                                              parameterSetSizeOut: &spsSize,
                                                              parameterSetCountOut: &spsCount,
                                                              nalUnitHeaderLengthOut: nil) == noErr,
           let spsPointer {
            sps = Data(bytes: spsPointer, count: spsSize)
        }
        var ppsSize = 0
        var ppsPointer: UnsafePointer<UInt8>?
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 1,
                                                              parameterSetPointerOut: &ppsPointer,
                                                              parameterSetSizeOut: &ppsSize,
                                                              parameterSetCountOut: nil,
                                                              nalUnitHeaderLengthOut: nil) == noErr,
           let ppsPointer {
            pps = Data(bytes: ppsPointer, count: ppsSize)
        }
    }

    deinit {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
    }
}

// MARK: - AAC Encoder (AudioToolbox)
import AudioToolbox

final class AACEncoder {
    private var converter: AudioConverterRef?
    private var aacBuffer = Data()
    private var pcmBuffer = Data()

    func encode(sampleBuffer: CMSampleBuffer) -> Data {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return Data() }

        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        guard let asbd else { return Data() }

        if converter == nil { setupConverter(inputFormat: asbd) }
        guard converter != nil else { return Data() }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard let dataPointer, totalLength > 0 else { return Data() }

        pcmBuffer = Data(bytes: dataPointer, count: totalLength)

        let outBufferSize = 1024
        var outBuffer = Data(count: outBufferSize)
        var outPacketDesc = AudioStreamPacketDescription()

        var ioOutputDataPacketSize: UInt32 = 1
        var outABL = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(outBufferSize),
                mData: nil
            )
        )

        let result = outBuffer.withUnsafeMutableBytes { outPtr -> OSStatus in
            outABL.mBuffers.mData = outPtr.baseAddress
            return pcmBuffer.withUnsafeBytes { pcmPtr -> OSStatus in
                var inABL = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: UInt32(asbd.mChannelsPerFrame),
                        mDataByteSize: UInt32(totalLength),
                        mData: UnsafeMutableRawPointer(mutating: pcmPtr.baseAddress!)
                    )
                )
                return AudioConverterConvertComplexBuffer(converter!, &ioOutputDataPacketSize,
                                                          &inABL, &outABL)
            }
        }

        guard result == noErr else { return Data() }
        let encodedSize = Int(outABL.mBuffers.mDataByteSize)
        return outBuffer.prefix(encodedSize)
    }

    private func setupConverter(inputFormat: AudioStreamBasicDescription) {
        var inFormat = inputFormat
        var outFormat = AudioStreamBasicDescription(
            mSampleRate: inputFormat.mSampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: inputFormat.mChannelsPerFrame,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        AudioConverterNew(&inFormat, &outFormat, &converter)
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
    }
}

// MARK: - FLV Packet Builder
enum FLVPacket {
    static func videoTag(nalus: [Data], timestamp: UInt32, isKeyframe: Bool) -> Data {
        var payload = Data()
        let frameType: UInt8 = isKeyframe ? 0x17 : 0x27
        payload.append(frameType)
        payload.append(0x01) // AVC NALU
        // composition time offset
        payload.append(contentsOf: [0x00, 0x00, 0x00])

        for nalu in nalus {
            var len = UInt32(nalu.count).bigEndian
            payload.append(Data(bytes: &len, count: 4))
            payload.append(nalu)
        }

        return wrapTag(type: 0x09, data: payload, timestamp: timestamp)
    }

    static func audioTag(aacData: Data, timestamp: UInt32) -> Data {
        var payload = Data()
        payload.append(0xAF) // AAC, 44100, stereo, 16-bit
        payload.append(0x01) // AAC raw
        payload.append(aacData)
        return wrapTag(type: 0x08, data: payload, timestamp: timestamp)
    }

    static func wrapTag(type: UInt8, data: Data, timestamp: UInt32) -> Data {
        var tag = Data()
        tag.append(type)

        let dataSize = UInt32(data.count)
        tag.append(UInt8((dataSize >> 16) & 0xFF))
        tag.append(UInt8((dataSize >> 8) & 0xFF))
        tag.append(UInt8(dataSize & 0xFF))

        tag.append(UInt8((timestamp >> 16) & 0xFF))
        tag.append(UInt8((timestamp >> 8) & 0xFF))
        tag.append(UInt8(timestamp & 0xFF))
        tag.append(UInt8((timestamp >> 24) & 0xFF)) // timestamp extended

        // stream ID = 0
        tag.append(contentsOf: [0x00, 0x00, 0x00])

        tag.append(data)

        // previous tag size
        let totalSize = UInt32(tag.count)
        var prevSize = totalSize.bigEndian
        tag.append(Data(bytes: &prevSize, count: 4))

        return tag
    }
}

// MARK: - RTMP Client (raw socket)
import Network

final class RTMPClient {
    let url: String
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "rtmp.client")
    private var connected = false
    private var handshakeDone = false
    private var host: String = ""
    private var port: UInt16 = 1935
    private var app: String = ""
    private var streamKey: String = ""

    init(url: String) {
        self.url = url
        parseURL()
    }

    func connect() {
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
        connection = NWConnection(to: endpoint, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.performHandshake()
            case .failed, .cancelled:
                self?.connected = false
                self?.handshakeDone = false
            default:
                break
            }
        }
        connection?.start(queue: queue)
    }

    func disconnect() {
        connected = false
        handshakeDone = false
        connection?.cancel()
        connection = nil
    }

    func send(_ data: Data) {
        guard connected, handshakeDone else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func parseURL() {
        var urlStr = url
        if urlStr.hasPrefix("rtmp://") { urlStr = String(urlStr.dropFirst(7)) }

        if let slashIdx = urlStr.firstIndex(of: "/") {
            let hostPart = String(urlStr[..<slashIdx])
            let pathPart = String(urlStr[urlStr.index(after: slashIdx)...])

            if let colonIdx = hostPart.firstIndex(of: ":") {
                host = String(hostPart[..<colonIdx])
                port = UInt16(String(hostPart[hostPart.index(after: colonIdx)...])) ?? 1935
            } else {
                host = hostPart
            }

            if let lastSlash = pathPart.lastIndex(of: "/") {
                app = String(pathPart[..<lastSlash])
                streamKey = String(pathPart[pathPart.index(after: lastSlash)...])
            } else {
                app = pathPart
            }
        }
    }

    private func performHandshake() {
        // C0 + C1
        var c0c1 = Data([0x03])
        var timestamp = UInt32(0).bigEndian
        c0c1.append(Data(bytes: &timestamp, count: 4))
        c0c1.append(Data(repeating: 0, count: 4)) // zero
        c0c1.append(Data((0..<1528).map { _ in UInt8.random(in: 0...255) }))

        connection?.send(content: c0c1, completion: .contentProcessed { [weak self] _ in
            self?.receiveHandshakeResponse()
        })
    }

    private func receiveHandshakeResponse() {
        // S0 + S1 + S2 = 1 + 1536 + 1536 = 3073
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 3073) { [weak self] data, _, _, _ in
            guard let self, let data, data.count >= 1537 else { return }
            // C2 = echo S1
            let s1 = data.subdata(in: 1..<1537)
            self.connection?.send(content: s1, completion: .contentProcessed { [weak self] _ in
                self?.handshakeDone = true
                self?.sendConnect()
            })
        }
    }

    private func sendConnect() {
        var data = Data()
        // AMF0 connect command
        data.append(amfString("connect"))
        data.append(amfNumber(1)) // transaction ID

        // command object
        data.append(0x03) // object marker
        data.append(amfProperty("app", stringValue: app))
        data.append(amfProperty("tcUrl", stringValue: "rtmp://\(host):\(port)/\(app)"))
        data.append(amfProperty("type", stringValue: "nonprivate"))
        data.append(amfProperty("flashVer", stringValue: "FMLE/3.0"))
        data.append(contentsOf: [0x00, 0x00, 0x09]) // object end

        sendChunk(data: data, chunkStreamID: 3, messageTypeID: 0x14, messageStreamID: 0)

        // After connect, wait briefly then send createStream + publish
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendCreateStream()
        }
    }

    private func sendCreateStream() {
        var data = Data()
        data.append(amfString("createStream"))
        data.append(amfNumber(2))
        data.append(0x05) // null
        sendChunk(data: data, chunkStreamID: 3, messageTypeID: 0x14, messageStreamID: 0)

        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendPublish()
        }
    }

    private func sendPublish() {
        var data = Data()
        data.append(amfString("publish"))
        data.append(amfNumber(0))
        data.append(0x05) // null
        data.append(amfString(streamKey))
        data.append(amfString("live"))
        sendChunk(data: data, chunkStreamID: 8, messageTypeID: 0x14, messageStreamID: 1)

        connected = true
        startReceiving()
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, isComplete, _ in
            guard let self, !isComplete else { return }
            self.startReceiving()
        }
    }

    // MARK: - RTMP chunk sending
    private func sendChunk(data: Data, chunkStreamID: UInt8, messageTypeID: UInt8, messageStreamID: UInt32) {
        var header = Data()
        header.append(chunkStreamID) // fmt=0 (full header), csid
        // timestamp
        header.append(contentsOf: [0x00, 0x00, 0x00])
        // message length (3 bytes big endian)
        let len = UInt32(data.count)
        header.append(UInt8((len >> 16) & 0xFF))
        header.append(UInt8((len >> 8) & 0xFF))
        header.append(UInt8(len & 0xFF))
        // message type
        header.append(messageTypeID)
        // message stream ID (little endian)
        var msid = messageStreamID
        header.append(Data(bytes: &msid, count: 4))

        var chunk = header
        chunk.append(data)
        connection?.send(content: chunk, completion: .contentProcessed { _ in })
    }

    // MARK: - AMF0
    private func amfString(_ s: String) -> Data {
        var data = Data()
        data.append(0x02) // string marker
        let bytes = Array(s.utf8)
        var len = UInt16(bytes.count).bigEndian
        data.append(Data(bytes: &len, count: 2))
        data.append(contentsOf: bytes)
        return data
    }

    private func amfNumber(_ n: Double) -> Data {
        var data = Data()
        data.append(0x00) // number marker
        var bits = n.bitPattern.bigEndian
        data.append(Data(bytes: &bits, count: 8))
        return data
    }

    private func amfProperty(_ key: String, stringValue: String) -> Data {
        var data = Data()
        let keyBytes = Array(key.utf8)
        var len = UInt16(keyBytes.count).bigEndian
        data.append(Data(bytes: &len, count: 2))
        data.append(contentsOf: keyBytes)
        // string value (with type marker)
        data.append(amfString(stringValue))
        return data
    }
}
