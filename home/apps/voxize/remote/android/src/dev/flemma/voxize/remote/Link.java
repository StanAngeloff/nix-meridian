package dev.flemma.voxize.remote;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import org.json.JSONException;
import org.json.JSONObject;

import android.os.Build;
import android.util.Log;

/**
 * The TCP connection to the server (voxize_remote/frames.py on the server): a kind byte, a big-endian 32-bit length,
 * the payload. Kind 'J' is a JSON object, kind 'A' is 24 kHz mono 16-bit PCM.
 *
 * Every connection opens with the challenge in both directions (pairing.py on the server, Pairing here). The server
 * proves it holds this client's secret before the client proves it does; until both have, nothing but the handshake goes
 * out and nothing from the server reaches the listener, so an impostor can never make the client record.
 *
 * One thread connects and reads, reconnecting while the service runs; one executor writes, so audio frames and
 * control messages leave in the order they were queued.
 */
final class Link {
    interface Listener {
        /** The server proved itself and accepted this client. */
        void onConnected();
        void onDisconnected(String reason);
        void onMessage(JSONObject message);
    }

    private static final String TAG = "VoxizeLink";
    static final int PROTOCOL = 2;
    private static final int CONNECT_TIMEOUT_MILLISECONDS = 5000;
    private static final int HANDSHAKE_TIMEOUT_MILLISECONDS = 10000;
    // The server answers each ping; silence this long means the connection is gone.
    private static final int READ_TIMEOUT_MILLISECONDS = 75000;
    private static final int PING_SECONDS = 25;
    private static final int RETRY_MILLISECONDS = 3000;
    // After a refusal (not paired, a server that failed its proof) there is no point in knocking every 3 seconds.
    private static final int REFUSED_RETRY_MILLISECONDS = 30000;
    private static final int MAXIMUM_PAYLOAD = 1 << 20;
    private static final int HANDSHAKE_PAYLOAD = 4096;

    /** The handshake failed; the message is for Stan. */
    private static final class Refused extends Exception {
        Refused(String message) {
            super(message);
        }
    }

    private final android.content.Context context;
    private final String host;
    private final int port;
    private final String deviceId;
    private final byte[] secret;
    private final Listener listener;
    private final ExecutorService writer = Executors.newSingleThreadExecutor();
    private final ScheduledExecutorService pinger = Executors.newSingleThreadScheduledExecutor();
    private final Object retryLock = new Object();
    private volatile boolean running;
    private volatile Socket socket;
    private volatile DataOutputStream output;
    private volatile boolean authenticated;
    private Thread thread;

    Link(android.content.Context context, String host, int port, String deviceId, byte[] secret, Listener listener) {
        this.context = context.getApplicationContext();
        this.host = host;
        this.port = port;
        this.deviceId = deviceId;
        this.secret = secret.clone();
        this.listener = listener;
    }

    void start() {
        running = true;
        thread = new Thread(this::run, "voxize-link");
        thread.start();
        pinger.scheduleWithFixedDelay(() -> sendJson(json("ping")), PING_SECONDS, PING_SECONDS, TimeUnit.SECONDS);
    }

    /** Stops waiting before the next attempt: `ssh cc` again is a good moment to try. */
    void retryNow() {
        synchronized (retryLock) {
            retryLock.notifyAll();
        }
    }

    void stop() {
        running = false;
        pinger.shutdownNow();
        closeSocket();
        synchronized (retryLock) {
            retryLock.notifyAll();
        }
        writer.shutdown();
    }

    /** Connected to a server that proved itself, and accepted by it. */
    boolean connected() {
        return authenticated && output != null;
    }

    static JSONObject json(String type) {
        JSONObject message = new JSONObject();
        try {
            message.put("type", type);
        } catch (JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
        return message;
    }

    void sendJson(JSONObject message) {
        send((byte) 'J', message.toString().getBytes(StandardCharsets.UTF_8), false);
    }

    void sendAudio(byte[] pcm) {
        send((byte) 'A', pcm, false);
    }

    private void sendHandshake(JSONObject message) {
        send((byte) 'J', message.toString().getBytes(StandardCharsets.UTF_8), true);
    }

    private void send(final byte kind, final byte[] payload, final boolean handshake) {
        if (writer.isShutdown()) {
            return;
        }
        writer.execute(() -> {
            DataOutputStream stream = output;
            // Only the handshake may leave before the server has proved itself.
            if (stream == null || (!handshake && !authenticated)) {
                return;
            }
            try {
                stream.writeByte(kind);
                stream.writeInt(payload.length);
                stream.write(payload);
                stream.flush();
            } catch (IOException error) {
                Log.w(TAG, "write failed", error);
                closeSocket();
            }
        });
    }

    private void closeSocket() {
        Socket current = socket;
        authenticated = false;
        output = null;
        if (current != null) {
            try {
                current.close();
            } catch (IOException ignored) {
                // Closing is all that is left to do.
            }
        }
    }

    private void run() {
        while (running) {
            String reason;
            int retry = RETRY_MILLISECONDS;
            try {
                Socket connection = new Socket();
                socket = connection;
                Tailnet.connect(context, connection, host, port, CONNECT_TIMEOUT_MILLISECONDS);
                connection.setTcpNoDelay(true);
                connection.setSoTimeout(HANDSHAKE_TIMEOUT_MILLISECONDS);
                output = new DataOutputStream(new BufferedOutputStream(connection.getOutputStream()));
                DataInputStream input = new DataInputStream(new BufferedInputStream(connection.getInputStream()));
                handshake(input);
                connection.setSoTimeout(READ_TIMEOUT_MILLISECONDS);
                read(input);
                reason = "the server closed the connection";
            } catch (Refused refused) {
                Log.w(TAG, "refused: " + refused.getMessage());
                reason = refused.getMessage();
                retry = REFUSED_RETRY_MILLISECONDS;
            } catch (Tailnet.Refused refused) {
                // Often Tailscale still connecting: tried again at the usual pace.
                Log.w(TAG, "not through Tailscale: " + refused.getMessage());
                reason = refused.getMessage();
            } catch (IOException | JSONException | RuntimeException error) {
                reason = Reasons.connection(error, host, port);
            }
            closeSocket();
            if (!running) {
                break;
            }
            listener.onDisconnected(reason);
            synchronized (retryLock) {
                if (running) {
                    try {
                        retryLock.wait(retry);
                    } catch (InterruptedException interrupted) {
                        return;
                    }
                }
            }
        }
    }

    private JSONObject readJson(DataInputStream input, int limit) throws IOException, JSONException, Refused {
        int kind = input.readUnsignedByte();
        int length = input.readInt();
        if (length < 0 || length > limit) {
            throw new IOException("frame of " + length + " bytes");
        }
        byte[] payload = new byte[length];
        input.readFully(payload);
        if (kind != 'J') {
            throw new Refused("the server sent audio before the handshake");
        }
        JSONObject message = new JSONObject(new String(payload, StandardCharsets.UTF_8));
        if ("error".equals(message.optString("type"))) {
            throw new Refused(message.optString("message", "the server refused this client"));
        }
        return message;
    }

    private void handshake(DataInputStream input) throws IOException, JSONException, Refused {
        byte[] clientNonce = Pairing.newNonce();
        JSONObject hello = json("hello");
        hello.put("protocol", PROTOCOL);
        hello.put("device", Build.MANUFACTURER + " " + Build.MODEL);
        hello.put("device_id", deviceId);
        hello.put("nonce", Pairing.hex(clientNonce));
        sendHandshake(hello);

        JSONObject challenge = readJson(input, HANDSHAKE_PAYLOAD);
        byte[] serverNonce = Pairing.unhex(challenge.optString("nonce", null), Pairing.NONCE_BYTES);
        if (!"challenge".equals(challenge.optString("type")) || serverNonce == null) {
            throw new Refused("the server did not send a challenge");
        }
        String expected = Pairing.serverProof(secret, clientNonce, serverNonce);
        if (!Pairing.proofsMatch(expected, challenge.optString("proof", null))) {
            throw new Refused("the server could not prove it is the one this client paired with");
        }
        JSONObject answer = json("answer");
        answer.put("proof", Pairing.clientProof(secret, clientNonce, serverNonce));
        sendHandshake(answer);

        // The server's first status says it accepted the proof; a refusal closes the connection instead.
        JSONObject first = readJson(input, MAXIMUM_PAYLOAD);
        if (!"status".equals(first.optString("type"))) {
            throw new Refused("the server did not accept this client");
        }
        authenticated = true;
        listener.onConnected();
        listener.onMessage(first);
    }

    private void read(DataInputStream input) throws IOException, JSONException {
        while (running) {
            int kind = input.readUnsignedByte();
            int length = input.readInt();
            if (length < 0 || length > MAXIMUM_PAYLOAD) {
                throw new IOException("frame of " + length + " bytes");
            }
            byte[] payload = new byte[length];
            input.readFully(payload);
            if (kind == 'J') {
                listener.onMessage(new JSONObject(new String(payload, StandardCharsets.UTF_8)));
            }
        }
    }
}
