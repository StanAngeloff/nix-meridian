package dev.flemma.voxize.remote;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.util.Log;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * The microphone, read on its own thread in 40 ms blocks of 24 kHz mono 16-bit PCM (Voxize's format). A device that
 * cannot record at 24 kHz records at 48 kHz and every pair of samples is averaged into one.
 */
final class Capture {
    interface Listener {
        /** The microphone is open and recording. */
        void onCapturing(int deviceRate, String source);
        void onAudio(byte[] pcm, float level);
        /** Recording ended; every block was passed to onAudio first. error is null when it was asked to stop. */
        void onCaptured(String error);
    }

    private static final String TAG = "VoxizeCapture";
    static final int RATE = 24000;
    private static final int BLOCK_SAMPLES = 960;

    private final Listener listener;
    private volatile AtomicBoolean live = new AtomicBoolean(false);

    Capture(Listener listener) {
        this.listener = listener;
    }

    boolean running() {
        return live.get();
    }

    void start() {
        if (live.get()) {
            return;
        }
        final AtomicBoolean run = new AtomicBoolean(true);
        live = run;
        Thread thread = new Thread(() -> run(run), "voxize-capture");
        thread.setPriority(Thread.MAX_PRIORITY);
        thread.start();
    }

    /** Asks the thread to finish its current block and end; onCaptured follows. */
    void stop() {
        live.set(false);
    }

    private void run(AtomicBoolean running) {
        int deviceRate = RATE;
        int minimum = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0) {
            deviceRate = RATE * 2;
            minimum = AudioRecord.getMinBufferSize(deviceRate, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT);
        }
        int factor = deviceRate / RATE;
        int blockBytes = BLOCK_SAMPLES * 2 * factor;
        AudioRecord recorder = null;
        String error = null;
        try {
            if (minimum <= 0) {
                throw new IllegalStateException("the microphone records neither 24 nor 48 kHz");
            }
            String source = "voice-recognition";
            try {
                recorder = open(MediaRecorder.AudioSource.VOICE_RECOGNITION, deviceRate, minimum, blockBytes);
            } catch (IllegalStateException unavailable) {
                source = "mic";
                recorder = open(MediaRecorder.AudioSource.MIC, deviceRate, minimum, blockBytes);
            }
            recorder.startRecording();
            if (recorder.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) {
                throw new IllegalStateException("the microphone did not start (in use by another app?)");
            }
            listener.onCapturing(deviceRate, source);
            byte[] block = new byte[blockBytes];
            while (running.get()) {
                int filled = 0;
                while (filled < blockBytes) {
                    int read = recorder.read(block, filled, blockBytes - filled);
                    if (read < 0) {
                        throw new IllegalStateException("microphone read failed: " + read);
                    }
                    filled += read;
                }
                byte[] pcm = factor == 1 ? block.clone() : halve(block);
                listener.onAudio(pcm, level(pcm));
            }
        } catch (RuntimeException failure) {
            Log.w(TAG, "capture failed", failure);
            error = failure.getMessage() != null ? failure.getMessage() : failure.toString();
        } finally {
            if (recorder != null) {
                try {
                    recorder.stop();
                } catch (IllegalStateException ignored) {
                    // It never started.
                }
                recorder.release();
            }
            running.set(false);
            listener.onCaptured(error);
        }
    }

    private static AudioRecord open(int source, int rate, int minimum, int blockBytes) {
        AudioRecord recorder = new AudioRecord(source, rate, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, Math.max(minimum, blockBytes * 4));
        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            recorder.release();
            throw new IllegalStateException("the microphone could not be opened");
        }
        return recorder;
    }

    /** 48 kHz to 24 kHz: the mean of each pair, a crude low-pass that is enough for speech. */
    private static byte[] halve(byte[] pcm) {
        byte[] out = new byte[pcm.length / 2];
        for (int in = 0, at = 0; in + 3 < pcm.length; in += 4, at += 2) {
            int first = (short) ((pcm[in] & 0xff) | (pcm[in + 1] << 8));
            int second = (short) ((pcm[in + 2] & 0xff) | (pcm[in + 3] << 8));
            int mean = (first + second) / 2;
            out[at] = (byte) mean;
            out[at + 1] = (byte) (mean >> 8);
        }
        return out;
    }

    /** 0 at -60 dBFS or quieter, 1 at full scale. */
    private static float level(byte[] pcm) {
        double sum = 0;
        int samples = pcm.length / 2;
        for (int at = 0; at + 1 < pcm.length; at += 2) {
            int sample = (short) ((pcm[at] & 0xff) | (pcm[at + 1] << 8));
            sum += (double) sample * sample;
        }
        if (samples == 0 || sum == 0) {
            return 0f;
        }
        double dbfs = 20 * Math.log10(Math.sqrt(sum / samples) / 32768.0);
        return (float) Math.max(0, Math.min(1, (dbfs + 60) / 60));
    }
}
