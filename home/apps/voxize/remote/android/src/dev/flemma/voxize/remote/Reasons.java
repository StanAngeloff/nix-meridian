package dev.flemma.voxize.remote;

import java.io.EOFException;
import java.net.SocketTimeoutException;

/**
 * Why a connection failed, in a sentence for the bubble and the checklist. Android's own messages name both ends'
 * addresses and ports, a timeout in milliseconds and an errno; only the errno says what to do.
 */
final class Reasons {
    private Reasons() {
    }

    static String connection(Throwable error, String host, int port) {
        String message = error.getMessage() != null ? error.getMessage() : error.toString();
        if (message.contains("ECONNREFUSED")) {
            return host + " is not taking connections on port " + port + ": is Voxize Remote set up on it?";
        }
        if (message.contains("ENETUNREACH") || message.contains("EHOSTUNREACH")) {
            return "cannot reach " + host + ": is Tailscale connected?";
        }
        if (error instanceof EOFException) {
            // The server closes on peers it will not talk to (not this tailnet's owner, say) without a word.
            return host + " closed the connection: its log says why (journalctl --user -u voxize-remote)";
        }
        if (error instanceof SocketTimeoutException) {
            return "no answer from " + host + ": is it awake and on Tailscale?";
        }
        return message;
    }
}
