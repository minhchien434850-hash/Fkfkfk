import AVFoundation
import MediaPlayer

// ======================== Chạy nền · Now Playing · Control Center ========================
extension TTSEngine {

    // ===== Now Playing (hiện ở Control Center / màn khoá) =====
    func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.removeTarget(nil); c.pauseCommand.removeTarget(nil); c.stopCommand.removeTarget(nil)
        c.playCommand.isEnabled = true; c.pauseCommand.isEnabled = true; c.stopCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in self?.pauseOrContinue(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pauseOrContinue(); return .success }
        c.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }
    }

    func updateNowPlaying(playing: Bool) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = "KENIOS đang đọc"
        info[MPMediaItemPropertyArtist] = "KENIOS AI"
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func startBackgroundMode() {
        activateSession()
        guard let silentData = createSilentWAV() else { return }
        do {
            let player = try AVAudioPlayer(data: silentData)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            self.silentPlayer = player
        } catch {
            print("Lỗi khởi tạo silent player: \(error)")
        }
    }

    func stopBackgroundMode() {
        silentPlayer?.stop()
        silentPlayer = nil
    }

    func createSilentWAV() -> Data? {
        let sampleRate: Int32 = 8000
        let channels: Int16 = 1
        let bps: Int16 = 16
        let seconds = 2
        let byteRate = sampleRate * Int32(channels) * Int32(bps / 8)
        let blockAlign = channels * (bps / 8)
        let dataSize = byteRate * Int32(seconds)

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var totalSizeLE = (dataSize + 36).littleEndian
        header.append(Data(bytes: &totalSizeLE, count: 4))
        header.append(contentsOf: "WAVEfmt ".utf8)
        var fmtSizeLE: Int32 = 16
        header.append(Data(bytes: &fmtSizeLE, count: 4))
        var formatLE: Int16 = 1 // PCM
        header.append(Data(bytes: &formatLE, count: 2))
        var channelsLE = channels.littleEndian
        header.append(Data(bytes: &channelsLE, count: 2))
        var sampleRateLE = sampleRate.littleEndian
        header.append(Data(bytes: &sampleRateLE, count: 4))
        var byteRateLE = byteRate.littleEndian
        header.append(Data(bytes: &byteRateLE, count: 4))
        var blockAlignLE = blockAlign.littleEndian
        header.append(Data(bytes: &blockAlignLE, count: 2))
        var bpsLE = bps.littleEndian
        header.append(Data(bytes: &bpsLE, count: 2))
        header.append(contentsOf: "data".utf8)
        var dataSizeLE = dataSize.littleEndian
        header.append(Data(bytes: &dataSizeLE, count: 4))

        let silence = Data(repeating: 0, count: Int(dataSize))
        header.append(silence)
        return header
    }
}
