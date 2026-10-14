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

/// Call mode fades other apps down in about half a second and back up in about a second: calm,
/// noticeable, never abrupt.
static const double kDuckDownTimeConstant = 0.15;
static const double kDuckUpTimeConstant = 0.35;

struct MPRenderState {
    // Shared with the main thread.
    _Atomic float targetGain;
    _Atomic float targetDuck;
    _Atomic bool hasReceivedSignal;
    _Atomic uint64_t callbackCount;
    // Audio thread only.
    float currentGain;
    float currentDuck;
    float rampCoefficient;
    float duckDownCoefficient;
    float duckUpCoefficient;
};

static float coefficient(double timeConstant, double sampleRate) {
    return (float)(1.0 - exp(-1.0 / (timeConstant * sampleRate)));
}

static float clampGain(float gain) {
    if (!(gain >= 0.0f)) return 0.0f; // also catches NaN
    return gain > kMaximumGain ? kMaximumGain : gain;
}

MPRenderState *MPRenderStateCreate(float gain, float duck, double sampleRate) {
    MPRenderState *state = calloc(1, sizeof(MPRenderState));
    if (state == NULL) return NULL;
    float clampedGain = clampGain(gain);
    float clampedDuck = clampGain(duck);
    atomic_init(&state->targetGain, clampedGain);
    atomic_init(&state->targetDuck, clampedDuck);
    atomic_init(&state->hasReceivedSignal, false);
    atomic_init(&state->callbackCount, 0);
    state->currentGain = clampedGain;
    state->currentDuck = clampedDuck;
    double rate = sampleRate > 0 ? sampleRate : 48000.0;
    state->rampCoefficient = coefficient(kRampTimeConstant, rate);
    state->duckDownCoefficient = coefficient(kDuckDownTimeConstant, rate);
    state->duckUpCoefficient = coefficient(kDuckUpTimeConstant, rate);
    return state;
}

void MPRenderStateDestroy(MPRenderState *state) {
    free(state);
}

void MPRenderSetGain(MPRenderState *state, float gain) {
    atomic_store_explicit(&state->targetGain, clampGain(gain), memory_order_relaxed);
}

void MPRenderSetDuck(MPRenderState *state, float level) {
    float clamped = clampGain(level);
    atomic_store_explicit(&state->targetDuck, clamped, memory_order_relaxed);
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
    const float duckTarget = atomic_load_explicit(&state->targetDuck, memory_order_relaxed);
    const float rampCoefficient = state->rampCoefficient;
    const float duckCoefficient = duckTarget < state->currentDuck ? state->duckDownCoefficient : state->duckUpCoefficient;
    float gain = state->currentGain;
    float duck = state->currentDuck;
    bool sawSignal = false;

    for (UInt32 frame = 0; frame < frames; frame++) {
        if (gain != target) {
            gain += (target - gain) * rampCoefficient;
            if (fabsf(target - gain) < 1e-5f) gain = target;
        }
        if (duck != duckTarget) {
            duck += (duckTarget - duck) * duckCoefficient;
            if (fabsf(duckTarget - duck) < 1e-5f) duck = duckTarget;
        }
        float l = left.data[frame * left.stride];
        float r = right.data[frame * right.stride];
        sawSignal = sawSignal || l != 0.0f || r != 0.0f;
        const float level = gain * duck;
        l *= level;
        r *= level;
        if (stereoOutput) {
            outLeft.data[frame * outLeft.stride] = l;
            outRight.data[frame * outRight.stride] = r;
        } else {
            outLeft.data[frame * outLeft.stride] = 0.5f * (l + r);
        }
    }

    state->currentGain = gain;
    state->currentDuck = duck;
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
