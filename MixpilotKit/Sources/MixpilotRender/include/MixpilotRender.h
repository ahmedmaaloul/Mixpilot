// The real-time part of Mixpilot: applies one app's gain to its tapped audio.
//
// Everything that runs on the audio thread is in this C module so it can be audited for
// real-time safety: no allocation, no locks, no Objective-C or Swift, no logging. The main
// thread talks to the audio thread only through the atomics inside MPRenderState.

#ifndef MIXPILOT_RENDER_H
#define MIXPILOT_RENDER_H

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Per-session state shared between the main thread and the audio thread. Opaque on purpose:
/// only the functions below touch it.
typedef struct MPRenderState MPRenderState;

/// Allocates a state with an initial gain (applied without a ramp) for audio at `sampleRate`.
/// Call off the audio thread. Returns NULL if out of memory.
MPRenderState *_Nullable MPRenderStateCreate(float gain, double sampleRate);

/// Frees the state. Only after the IOProc using it has been stopped and destroyed.
void MPRenderStateDestroy(MPRenderState *_Nullable state);

/// Sets the gain the audio thread ramps to (0 = silent, 1 = unchanged). Values above 1 are
/// clamped to 1: Mixpilot never amplifies. Any thread.
void MPRenderSetGain(MPRenderState *_Nonnull state, float gain);

/// The gain the audio thread ramps to.
float MPRenderTargetGain(const MPRenderState *_Nonnull state);

/// True once any non-zero input sample has arrived. A tap without the System Audio Recording
/// permission only delivers zeros.
bool MPRenderHasReceivedSignal(const MPRenderState *_Nonnull state);

/// Number of times the audio thread has rendered (to tell whether IO is running).
uint64_t MPRenderCallbackCount(const MPRenderState *_Nonnull state);

/// Renders one buffer: reads the tap's stereo input, applies the smoothed gain (never above 1)
/// and writes it to the output channels. Extra output channels are silenced;
/// a mono output gets the average of left and right. Buffers must be 32-bit float, interleaved or
/// not. Real-time safe.
void MPRenderProcess(MPRenderState *_Nonnull state,
                     const AudioBufferList *_Nonnull input,
                     AudioBufferList *_Nonnull output);

/// The IOProc for the aggregate device. `clientData` is the session's MPRenderState.
OSStatus MPRenderIOProc(AudioObjectID device,
                        const AudioTimeStamp *_Nonnull now,
                        const AudioBufferList *_Nonnull inputData,
                        const AudioTimeStamp *_Nonnull inputTime,
                        AudioBufferList *_Nonnull outputData,
                        const AudioTimeStamp *_Nonnull outputTime,
                        void *_Nullable clientData);

#ifdef __cplusplus
}
#endif

#endif
