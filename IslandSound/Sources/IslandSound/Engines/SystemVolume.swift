import Foundation
import CoreAudio

/// Adjusts the default output device's volume via CoreAudio, used by the
/// "volume up" / "volume down" voice commands (Section 8.4).
enum SystemVolume {
    /// Adjusts the current output volume by `delta` (e.g. `0.10` for +10%),
    /// clamped to `0...1`. No-ops if no output device is available.
    static func adjust(by delta: Float) {
        guard let deviceID = defaultOutputDevice(), let current = volume(for: deviceID) else { return }
        let newVolume = max(0, min(1, current + delta))
        set(volume: newVolume, for: deviceID)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    private static func volume(for deviceID: AudioDeviceID) -> Float? {
        var volume = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    private static func set(volume: Float, for deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var newVolume = volume
        _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &newVolume)
    }
}
