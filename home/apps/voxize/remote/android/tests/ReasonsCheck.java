package dev.flemma.voxize.remote;

import java.net.ConnectException;
import java.net.SocketTimeoutException;

public final class ReasonsCheck {
    static void expect(String actual, String expected) {
        if (!actual.equals(expected)) {
            throw new AssertionError("got: " + actual + "\nwanted: " + expected);
        }
    }

    public static void main(String[] arguments) {
        String host = "stan-latitude.bopp-spica.ts.net";
        // Android's texts, as the A54 showed them.
        expect(Reasons.connection(new ConnectException("failed to connect to " + host + "/100.111.213.99 (port 8787) from "
                + "/100.116.170.12 (port 34298) after 5000ms: isConnected failed: ECONNREFUSED (Connection refused)"), host, 8787),
                host + " is not taking connections on port 8787: is Voxize Remote set up on it?");
        expect(Reasons.connection(new ConnectException("failed to connect to " + host + " (port 7223): connect failed: "
                + "ENETUNREACH (Network is unreachable)"), host, 7223), "cannot reach " + host + ": is Tailscale connected?");
        expect(Reasons.connection(new SocketTimeoutException("failed to connect to " + host + " (port 7223) after 5000ms"),
                host, 7223), "no answer from " + host + ": is it awake and on Tailscale?");
        expect(Reasons.connection(new java.io.EOFException(), host, 7223), host + " closed the connection: its log says why (journalctl --user -u voxize-remote)");
        expect(Reasons.connection(new java.io.IOException("frame of 9 bytes"), host, 7223), "frame of 9 bytes");
        System.out.println("Reasons: 5 checks pass");
    }
}
