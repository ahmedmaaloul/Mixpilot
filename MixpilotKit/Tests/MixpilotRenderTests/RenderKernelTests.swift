import CoreAudio
import MixpilotRender
import Testing

/// An AudioBufferList with float buffers of `channelsPerBuffer` channels each, freed on deinit.
final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(frames: Int, channelsPerBuffer: [Int], fill: (Int, Int) -> Float = { _, _ in 0 }) {
        // allocate(maximumBuffers:) traps on 0; an empty list is 1 slot with a count of 0.
        list = AudioBufferList.allocate(maximumBuffers: max(1, channelsPerBuffer.count))
        list.count = channelsPerBuffer.count
        var channelBase = 0
        for (index, channels) in channelsPerBuffer.enumerated() {
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames * channels)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    samples[frame * channels + channel] = fill(frame, channelBase + channel)
                }
            }
            storage.append(samples)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(frames * channels * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(samples)
            )
            channelBase += channels
        }
    }

    /// Sample at `frame` of the overall channel `channel`.
    func sample(_ frame: Int, channel: Int) -> Float {
        var base = 0
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            if channel < base + channels {
                return buffer.mData!.assumingMemoryBound(to: Float.self)[frame * channels + channel - base]
            }
            base += channels
        }
        fatalError("no channel \(channel)")
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

private func render(_ state: OpaquePointer, _ input: Buffers, _ output: Buffers) {
    MPRenderProcess(state, input.list.unsafePointer, output.list.unsafeMutablePointer)
}

@Suite("Render kernel")
struct RenderKernelTests {
    let rate = 48_000.0

    @Test func unityGainPassesInterleavedStereoThrough() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 256, channelsPerBuffer: [2]) { frame, channel in
            Float(frame % 7) * 0.1 * (channel == 0 ? 1 : -1)
        }
        let output = Buffers(frames: 256, channelsPerBuffer: [2])
        render(state, input, output)
        for frame in 0..<256 {
            #expect(output.sample(frame, channel: 0) == input.sample(frame, channel: 0))
            #expect(output.sample(frame, channel: 1) == input.sample(frame, channel: 1))
        }
    }

    @Test func nonInterleavedInputReachesInterleavedOutput() throws {
        let state = try #require(MPRenderStateCreate(0.5, 1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 64, channelsPerBuffer: [1, 1]) { _, channel in channel == 0 ? 0.4 : -0.2 }
        let output = Buffers(frames: 64, channelsPerBuffer: [2])
        render(state, input, output)
        #expect(output.sample(10, channel: 0) == 0.2)
        #expect(output.sample(10, channel: 1) == -0.1)
    }

    @Test func gainChangeRampsWithoutJumps() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        MPRenderSetGain(state, 0)
        let frames = 4_800 // 100 ms
        let input = Buffers(frames: frames, channelsPerBuffer: [2]) { _, _ in 0.5 }
        let output = Buffers(frames: frames, channelsPerBuffer: [2])
        render(state, input, output)

        // The first sample is still almost at full level: no step.
        #expect(output.sample(0, channel: 0) > 0.49)
        var previous = output.sample(0, channel: 0)
        for frame in 1..<frames {
            let value = output.sample(frame, channel: 0)
            #expect(value <= previous)
            #expect(previous - value < 0.01)
            previous = value
        }
        // After 100 ms (more than 6 time constants) it is effectively silent.
        #expect(previous < 0.002)
    }

    @Test func rampContinuesAcrossBuffers() throws {
        let state = try #require(MPRenderStateCreate(0, 1, rate))
        defer { MPRenderStateDestroy(state) }
        MPRenderSetGain(state, 1)
        let input = Buffers(frames: 128, channelsPerBuffer: [2]) { _, _ in 1 }
        let first = Buffers(frames: 128, channelsPerBuffer: [2])
        let second = Buffers(frames: 128, channelsPerBuffer: [2])
        render(state, input, first)
        render(state, input, second)
        let end = first.sample(127, channel: 0)
        let start = second.sample(0, channel: 0)
        #expect(start > end)
        #expect(start - end < 0.01)
    }

    @Test func monoOutputGetsTheAverage() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 32, channelsPerBuffer: [2]) { _, channel in channel == 0 ? 0.6 : 0.2 }
        let output = Buffers(frames: 32, channelsPerBuffer: [1])
        render(state, input, output)
        #expect(abs(output.sample(5, channel: 0) - 0.4) < 1e-6)
    }

    @Test func extraOutputChannelsAreSilent() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 32, channelsPerBuffer: [2]) { _, _ in 0.3 }
        let output = Buffers(frames: 32, channelsPerBuffer: [4]) { _, _ in 9 } // garbage before render
        render(state, input, output)
        #expect(output.sample(3, channel: 0) == 0.3)
        #expect(output.sample(3, channel: 1) == 0.3)
        #expect(output.sample(3, channel: 2) == 0)
        #expect(output.sample(3, channel: 3) == 0)
    }

    @Test func monoInputPlaysOnBothSides() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 16, channelsPerBuffer: [1]) { _, _ in 0.25 }
        let output = Buffers(frames: 16, channelsPerBuffer: [2])
        render(state, input, output)
        #expect(output.sample(0, channel: 0) == 0.25)
        #expect(output.sample(0, channel: 1) == 0.25)
    }

    @Test func neverAmplifies() throws {
        // Even if asked for more, the output is never louder than the app's own sound.
        let state = try #require(MPRenderStateCreate(2, 1, rate))
        defer { MPRenderStateDestroy(state) }
        #expect(MPRenderTargetGain(state) == 1)
        MPRenderSetGain(state, 3)
        let input = Buffers(frames: 4, channelsPerBuffer: [2]) { frame, _ in [0.3, 0.8, -0.8, 1][frame] }
        let output = Buffers(frames: 4, channelsPerBuffer: [2])
        render(state, input, output)
        for frame in 0..<4 {
            #expect(output.sample(frame, channel: 0) == input.sample(frame, channel: 0))
        }
    }

    @Test func signalIsDetectedOnlyForNonZeroInput() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        let silence = Buffers(frames: 64, channelsPerBuffer: [2])
        let output = Buffers(frames: 64, channelsPerBuffer: [2])
        render(state, silence, output)
        #expect(!MPRenderHasReceivedSignal(state))
        #expect(MPRenderCallbackCount(state) == 1)
        let sound = Buffers(frames: 64, channelsPerBuffer: [2]) { frame, _ in frame == 40 ? 0.01 : 0 }
        render(state, sound, output)
        #expect(MPRenderHasReceivedSignal(state))
    }

    @Test func invalidGainsAreClamped() throws {
        let state = try #require(MPRenderStateCreate(.nan, 1, rate))
        defer { MPRenderStateDestroy(state) }
        #expect(MPRenderTargetGain(state) == 0)
        MPRenderSetGain(state, 100)
        #expect(MPRenderTargetGain(state) == 1)
        MPRenderSetGain(state, -1)
        #expect(MPRenderTargetGain(state) == 0)
    }

    @Test func missingInputLeavesOutputSilent() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 16, channelsPerBuffer: [])
        let output = Buffers(frames: 16, channelsPerBuffer: [2]) { _, _ in 5 }
        render(state, input, output)
        #expect(output.sample(0, channel: 0) == 0)
    }
}

@Suite("Render kernel: call mode fades")
struct DuckTests {
    let rate = 48_000.0

    /// Renders `seconds` of a constant 0.5 signal and returns the last left sample.
    func level(after seconds: Double, _ state: OpaquePointer) -> Float {
        let frames = Int(seconds * rate)
        let input = Buffers(frames: frames, channelsPerBuffer: [2]) { _, _ in 0.5 }
        let output = Buffers(frames: frames, channelsPerBuffer: [2])
        MPRenderProcess(state, input.list.unsafePointer, output.list.unsafeMutablePointer)
        return output.sample(frames - 1, channel: 0)
    }

    @Test func duckingFadesDownInAboutHalfASecond() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        MPRenderSetDuck(state, 0.2)
        // Still clearly audible after 50 ms: a fade, not a cut.
        #expect(level(after: 0.05, state) > 0.35)
        // Within 3 % of the lowered level after half a second more.
        let settled = level(after: 0.5, state)
        #expect(abs(settled - 0.1) < 0.015)
    }

    @Test func comingBackUpIsSlowerThanGoingDown() throws {
        let down = try #require(MPRenderStateCreate(1, 1, rate))
        let up = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(down); MPRenderStateDestroy(up) }
        MPRenderSetDuck(up, 0)
        _ = level(after: 2, up)            // fully ducked
        MPRenderSetDuck(down, 0)
        MPRenderSetDuck(up, 1)
        let afterDown = 0.5 - level(after: 0.2, down)  // how far it fell from 0.5
        let afterUp = level(after: 0.2, up)            // how far it rose from 0
        #expect(afterUp < afterDown)
        #expect(abs(level(after: 1.5, up) - 0.5) < 0.01)
    }

    @Test func duckMultipliesTheVolume() throws {
        let state = try #require(MPRenderStateCreate(0.5, 1, rate))
        defer { MPRenderStateDestroy(state) }
        MPRenderSetDuck(state, 0.2)
        #expect(abs(level(after: 2, state) - 0.05) < 0.001)
    }

    @Test func volumeChangesStayQuickWhileDucked() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        MPRenderSetDuck(state, 0.5)
        _ = level(after: 2, state)
        MPRenderSetGain(state, 0.5)
        // The volume ramp (15 ms) is done in 100 ms; the duck stays where it was.
        #expect(abs(level(after: 0.1, state) - 0.125) < 0.002)
    }

    @Test func duckIsClampedToNeverAmplify() throws {
        let state = try #require(MPRenderStateCreate(1, 1, rate))
        defer { MPRenderStateDestroy(state) }
        MPRenderSetDuck(state, 5)
        #expect(level(after: 0.5, state) == 0.5)
    }
}
