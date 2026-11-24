package dev.flemma.voxize.remote;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * The client's half of the server's pairing.py: the proofs exchanged on every connection, and the commitment and code
 * of pairing. Every byte here must match the Python side.
 */
final class Pairing {
    static final int NONCE_BYTES = 32;
    private static final byte[] SERVER_LABEL = "voxize-remote server".getBytes(StandardCharsets.US_ASCII);
    private static final byte[] CLIENT_LABEL = "voxize-remote client".getBytes(StandardCharsets.US_ASCII);
    private static final byte[] CONFIRM_LABEL = "voxize-remote confirm".getBytes(StandardCharsets.US_ASCII);
    private static final SecureRandom RANDOM = new SecureRandom();

    private Pairing() {
    }

    static byte[] newNonce() {
        byte[] nonce = new byte[NONCE_BYTES];
        RANDOM.nextBytes(nonce);
        return nonce;
    }

    private static byte[] mac(byte[] secret, byte[]... parts) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret, "HmacSHA256"));
            for (byte[] part : parts) {
                mac.update(part);
            }
            return mac.doFinal();
        } catch (GeneralSecurityException impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    /** HMAC(secret, label, 0, client nonce, server nonce), as pairing.py's _mac. */
    private static String proof(byte[] secret, byte[] label, byte[] clientNonce, byte[] serverNonce) {
        return hex(mac(secret, label, new byte[] {0}, clientNonce, serverNonce));
    }

    static String serverProof(byte[] secret, byte[] clientNonce, byte[] serverNonce) {
        return proof(secret, SERVER_LABEL, clientNonce, serverNonce);
    }

    static String clientProof(byte[] secret, byte[] clientNonce, byte[] serverNonce) {
        return proof(secret, CLIENT_LABEL, clientNonce, serverNonce);
    }

    /** Constant-time comparison of two proofs. */
    static boolean proofsMatch(String expected, String received) {
        return received != null && MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.US_ASCII), received.getBytes(StandardCharsets.US_ASCII));
    }

    /** SHA-256 of the pairing nonce, sent before the secret arrives (pairing.py explains why). */
    static String commitment(byte[] pairingNonce) {
        try {
            return hex(MessageDigest.getInstance("SHA-256").digest(pairingNonce));
        } catch (GeneralSecurityException impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    /** The six digits this client shows and Stan types on the server: "123 456". */
    static String confirmationCode(byte[] secret, byte[] pairingNonce) {
        byte[] digest = mac(secret, CONFIRM_LABEL, new byte[] {0}, pairingNonce);
        long number = ((digest[0] & 0xffL) << 24 | (digest[1] & 0xffL) << 16 | (digest[2] & 0xffL) << 8
                | (digest[3] & 0xffL)) % 1_000_000L;
        return String.format(java.util.Locale.ROOT, "%03d %03d", number / 1000, number % 1000);
    }

    static String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            out.append(Character.forDigit((value >> 4) & 0xf, 16)).append(Character.forDigit(value & 0xf, 16));
        }
        return out.toString();
    }

    /** null unless the text is exactly {@code length} bytes of hexadecimal. */
    static byte[] unhex(String text, int length) {
        if (text == null || text.length() != length * 2) {
            return null;
        }
        byte[] bytes = new byte[length];
        for (int at = 0; at < length; at++) {
            int high = Character.digit(text.charAt(2 * at), 16);
            int low = Character.digit(text.charAt(2 * at + 1), 16);
            if (high < 0 || low < 0) {
                return null;
            }
            bytes[at] = (byte) (high << 4 | low);
        }
        return bytes;
    }
}
