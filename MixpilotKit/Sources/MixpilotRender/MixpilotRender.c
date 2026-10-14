#include "MixpilotRender.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

/// Time constant of the gain ramp. 15 ms is fast enough to feel instant while dragging a slider
/// and slow enough that a jump from 100 % to 0 % doesn't click.
static const double kRampTimeConstant = 0.015;

/// Mixpilot only ever makes apps quieter: the audio thread never amplifies, whatever it is told.
static const float kMaximumGain = 1.0f;

struct MPRenderState {
    // Shared with the main thread.
    _Atomic float targetGain;
    _Atomic bool hasReceivedSignal;
    _Atomic uint64_t callbackCount;
    // Audio thread only.
    float currentGain;
    float rampCoefficient;
};

static float clampGain(float gain) {
    if (!(gain >= 0.0f)) return 0.0f; // also catches NaN
    return gain > kMaximumGain ? kMaximumGain : gain;
}

MPRenderState *MPRenderStateCreate(float gain, double sampleRate) {
    MPRenderState *state = calloc(1, sizeof(MPRenderState));
    if (state == NULL) return NULL;
    float clamped = clampGain(gain);
    atomic_init(&state->targetGain, clamped);
    atomic_init(&state->hasReceivedSignal, false);
    atomic_init(&state->callbackCount, 0);
    state->currentGain = clamped;
    double rate = sampleRate > 0 ? sampleRate : 48000.0;
    state->rampCoefficient = (float)(1.0 - exp(-1.0 / (kRampTimeConstant * rate)));
    return state;
}

void MPRenderStateDestroy(MPRenderState *state) {
    free(state);
}

void MPRenderSetGain(MPRenderState *state, float gain) {
    atomic_store_explicit(&state->targetGain, clampGain(gain), memory_order_relaxed);
}

float MPRenderTargetGain(const MPRenderState *state) {
    return atomic_load_explicit(&((MPRenderState *)state)->targetGain, memory_order_relaxed);
}

bool MPRenderHasReceivedSignal(const MPRenderState *state) {
    return atomic_load_explicit(&((MPRenderState *)state)->hasReceivedSignal, memory_order_relaxed);
}

uint64_t MPRenderCallbackCount(const MPRenderState *state) {
    return atomic_load_explicit(&((MPRenderState *)state)->callbackCount, memory_order_relaxed);
}

/// One channel inside an AudioBufferList: where its first sample is and how far apart samples are.
typedef struct {
    float *data;
    UInt32 stride;
    UInt32 frames;
} Channel;

static UInt32 channelCount(const AudioBufferList *list) {
    UInt32 count = 0;
    for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
        count += list->mBuffers[i].mNumberChannels;
    }
    return count;
}

/// Finds channel `index` across the list's buffers (interleaved or not).
static bool findChannel(const AudioBufferList *list, UInt32 index, Channel *channel) {
    UInt32 first = 0;
    for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
        const AudioBuffer *buffer = &list->mBuffers[i];
        UInt32 channels = buffer->mNumberChannels;
        if (channels == 0 || buffer->mData == NULL) {
            continue;
        }
        if (index < first + channels) {
            channel->data = (float *)buffer->mData + (index - first);
            channel->stride = channels;
            channel->frames = buffer->mDataByteSize / (UInt32)(sizeof(float) * channels);
            return true;
        }
        first += channels;
    }
    return false;
}

void MPRenderProcess(MPRenderState *state, const AudioBufferList *input, AudioBufferList *output) {
    atomic_fetch_add_explicit(&state->callbackCount, 1, memory_order_relaxed);

    for (UInt32 i = 0; i < output->mNumberBuffers; i++) {
        if (output->mBuffers[i].mData != NULL) {
            memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
        }
    }

    Channel left, right, outLeft, outRight;
    if (!findChannel(input, 0, &left) || !findChannel(output, 0, &outLeft)) {
        return; // Nothing to read or nowhere to write: output stays silent.
    }
    if (!findChannel(input, 1, &right)) {
        right = left; // Mono input: same signal on both sides.
    }
    bool stereoOutput = channelCount(output) >= 2 && findChannel(output, 1, &outRight);

    UInt32 frames = left.frames;
    if (right.frames < frames) frames = right.frames;
    if (outLeft.frames < frames) frames = outLeft.frames;
    if (stereoOutput && outRight.frames < frames) frames = outRight.frames;

    const float target = atomic_load_explicit(&state->targetGain, memory_order_relaxed);
    const float coefficient = state->rampCoefficient;
    float gain = state->currentGain;
    bool sawSignal = false;

    for (UInt32 frame = 0; frame < frames; frame++) {
        if (gain != target) {
            gain += (target - gain) * coefficient;
            if (fabsf(target - gain) < 1e-5f) gain = target;
        }
        float l = left.data[frame * left.stride];
        float r = right.data[frame * right.stride];
        sawSignal = sawSignal || l != 0.0f || r != 0.0f;
        l *= gain;
        r *= gain;
        if (stereoOutput) {
            outLeft.data[frame * outLeft.stride] = l;
            outRight.data[frame * outRight.stride] = r;
        } else {
            outLeft.data[frame * outLeft.stride] = 0.5f * (l + r);
        }
    }

    state->currentGain = gain;
    if (sawSignal && !atomic_load_explicit(&state->hasReceivedSignal, memory_order_relaxed)) {
        atomic_store_explicit(&state->hasReceivedSignal, true, memory_order_relaxed);
    }
}

OSStatus MPRenderIOProc(AudioObjectID device,
                        const AudioTimeStamp *now,
                        const AudioBufferList *inputData,
                        const AudioTimeStamp *inputTime,
                        AudioBufferList *outputData,
                        const AudioTimeStamp *outputTime,
                        void *clientData) {
    (void)device;
    (void)now;
    (void)inputTime;
    (void)outputTime;
    if (clientData != NULL) {
        MPRenderProcess((MPRenderState *)clientData, inputData, outputData);
    }
    return noErr;
}
