import CoreAudio
import MixpilotRender
import Testing

/// An AudioBufferList with float buffers of `channelsPerBuffer` channels each, freed on deinit.
private final class Buffers {
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
        let state = try #require(MPRenderStateCreate(1, rate))
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
        let state = try #require(MPRenderStateCreate(0.5, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 64, channelsPerBuffer: [1, 1]) { _, channel in channel == 0 ? 0.4 : -0.2 }
        let output = Buffers(frames: 64, channelsPerBuffer: [2])
        render(state, input, output)
        #expect(output.sample(10, channel: 0) == 0.2)
        #expect(output.sample(10, channel: 1) == -0.1)
    }

    @Test func gainChangeRampsWithoutJumps() throws {
        let state = try #require(MPRenderStateCreate(1, rate))
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
        let state = try #require(MPRenderStateCreate(0, rate))
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
        let state = try #require(MPRenderStateCreate(1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 32, channelsPerBuffer: [2]) { _, channel in channel == 0 ? 0.6 : 0.2 }
        let output = Buffers(frames: 32, channelsPerBuffer: [1])
        render(state, input, output)
        #expect(abs(output.sample(5, channel: 0) - 0.4) < 1e-6)
    }

    @Test func extraOutputChannelsAreSilent() throws {
        let state = try #require(MPRenderStateCreate(1, rate))
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
        let state = try #require(MPRenderStateCreate(1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 16, channelsPerBuffer: [1]) { _, _ in 0.25 }
        let output = Buffers(frames: 16, channelsPerBuffer: [2])
        render(state, input, output)
        #expect(output.sample(0, channel: 0) == 0.25)
        #expect(output.sample(0, channel: 1) == 0.25)
    }

    @Test func boostIsLinearBelowTheLimiterAndSoftAbove() throws {
        let state = try #require(MPRenderStateCreate(2, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 4, channelsPerBuffer: [2]) { frame, _ in [0.3, 0.8, -0.8, 1][frame] }
        let output = Buffers(frames: 4, channelsPerBuffer: [2])
        render(state, input, output)
        #expect(abs(output.sample(0, channel: 0) - 0.6) < 1e-6)
        let loud = output.sample(1, channel: 0)
        #expect(loud > 0.9 && loud < 1)
        #expect(output.sample(2, channel: 0) == -loud)
        #expect(output.sample(3, channel: 0) <= 1)
    }

    @Test func signalIsDetectedOnlyForNonZeroInput() throws {
        let state = try #require(MPRenderStateCreate(1, rate))
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
        let state = try #require(MPRenderStateCreate(.nan, rate))
        defer { MPRenderStateDestroy(state) }
        #expect(MPRenderTargetGain(state) == 0)
        MPRenderSetGain(state, 100)
        #expect(MPRenderTargetGain(state) == 4)
        MPRenderSetGain(state, -1)
        #expect(MPRenderTargetGain(state) == 0)
    }

    @Test func missingInputLeavesOutputSilent() throws {
        let state = try #require(MPRenderStateCreate(1, rate))
        defer { MPRenderStateDestroy(state) }
        let input = Buffers(frames: 16, channelsPerBuffer: [])
        let output = Buffers(frames: 16, channelsPerBuffer: [2]) { _, _ in 5 }
        render(state, input, output)
        #expect(output.sample(0, channel: 0) == 0)
    }
}
