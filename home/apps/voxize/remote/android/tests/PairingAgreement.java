package dev.flemma.voxize.remote;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

/**
 * Pairing's answers for the server's tests to hold against pairing.py: one line in (secret, client nonce, server
 * nonce, pairing nonce, all hex), one line out (server proof, client proof, commitment, confirmation code).
 */
public final class PairingAgreement {
    public static void main(String[] arguments) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII));
        for (String line = input.readLine(); line != null; line = input.readLine()) {
            String[] fields = line.trim().split(" ");
            byte[] secret = Pairing.unhex(fields[0], 32);
            byte[] clientNonce = Pairing.unhex(fields[1], 32);
            byte[] serverNonce = Pairing.unhex(fields[2], 32);
            byte[] pairingNonce = Pairing.unhex(fields[3], 32);
            System.out.println(Pairing.serverProof(secret, clientNonce, serverNonce) + " "
                    + Pairing.clientProof(secret, clientNonce, serverNonce) + " "
                    + Pairing.commitment(pairingNonce) + " "
                    + Pairing.confirmationCode(secret, pairingNonce).replace(" ", "_"));
        }
    }
}
