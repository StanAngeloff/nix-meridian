package dev.flemma.voxize.remote;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.Closeable;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * Pairing with the server while `voxize-remote pair` holds a window open on the server (pairing.py there). Blocking;
 * MainActivity runs it on a background thread and shows the code in between.
 */
final class PairingClient implements Closeable {
    /** What the server offered: kept only once both screens confirmed the code. */
    static final class Offer {
        final String deviceId;
        final byte[] secret;
        final String server;
        final String code;

        Offer(String deviceId, byte[] secret, String server, byte[] pairingNonce) {
            this.deviceId = deviceId;
            this.secret = secret;
            this.server = server;
            this.code = Pairing.confirmationCode(secret, pairingNonce);
        }
    }

    /** The server refused or the pairing was not confirmed; the message is for Stan. */
    static final class Refused extends Exception {
        Refused(String message) {
            super(message);
        }
    }

    private static final int CONNECT_TIMEOUT_MILLISECONDS = 5000;
    // The server's side waits up to two minutes for Stan's answer there.
    private static final int ANSWER_TIMEOUT_MILLISECONDS = 150000;
    private static final int MAXIMUM_PAYLOAD = 4096;

    private final Socket socket = new Socket();
    private final DataInputStream input;
    private final DataOutputStream output;

    PairingClient(android.content.Context context, String host, int port) throws IOException {
        Tailnet.connect(context, socket, host, port, CONNECT_TIMEOUT_MILLISECONDS);
        socket.setSoTimeout(ANSWER_TIMEOUT_MILLISECONDS);
        input = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
        output = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream()));
    }

    /** Commits to a fresh nonce, takes the server's offer, reveals the nonce; the offer with the code to show. */
    Offer request(String deviceName) throws IOException, JSONException, Refused {
        byte[] pairingNonce = Pairing.newNonce();
        JSONObject request = Link.json("pair");
        request.put("protocol", Link.PROTOCOL);
        request.put("device", deviceName);
        request.put("commitment", Pairing.commitment(pairingNonce));
        write(request);
        JSONObject offer = read();
        byte[] secret = Pairing.unhex(offer.optString("secret", null), 32);
        String deviceId = offer.optString("device_id", "");
        if (!"pairing".equals(offer.optString("type")) || secret == null || deviceId.isEmpty()) {
            throw new Refused("the server sent no pairing offer");
        }
        JSONObject reveal = Link.json("reveal");
        reveal.put("nonce", Pairing.hex(pairingNonce));
        write(reveal);
        return new Offer(deviceId, secret, offer.optString("server", "the server"), pairingNonce);
    }

    /** Blocks until Stan has typed the code on the server: returns when it matched, Refused when it did not. */
    void awaitResult() throws IOException, JSONException, Refused {
        JSONObject result = read();
        if (!"paired".equals(result.optString("type"))) {
            throw new Refused("the server did not pair this client");
        }
    }

    void reject() {
        try {
            write(Link.json("pair_rejected"));
        } catch (IOException ignored) {
            // Closing below ends the pairing either way.
        }
    }

    private void write(JSONObject message) throws IOException {
        byte[] payload = message.toString().getBytes(StandardCharsets.UTF_8);
        output.writeByte('J');
        output.writeInt(payload.length);
        output.write(payload);
        output.flush();
    }

    private JSONObject read() throws IOException, JSONException, Refused {
        int kind = input.readUnsignedByte();
        int length = input.readInt();
        if (kind != 'J' || length < 0 || length > MAXIMUM_PAYLOAD) {
            throw new IOException("unexpected frame from the server");
        }
        byte[] payload = new byte[length];
        input.readFully(payload);
        JSONObject message = new JSONObject(new String(payload, StandardCharsets.UTF_8));
        if ("error".equals(message.optString("type"))) {
            throw new Refused(message.optString("message", "the server refused"));
        }
        return message;
    }

    @Override
    public void close() {
        try {
            socket.close();
        } catch (IOException ignored) {
            // Nothing left to do.
        }
    }
}
