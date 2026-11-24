package dev.flemma.voxize.remote;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;

import java.io.IOException;
import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.UnknownHostException;

/**
 * The client talks to Tailscale addresses only, and only through Tailscale. Its socket is bound to the VPN network
 * Android routes this app through, and refused when there is none: Tailscale's split tunneling can leave an app out,
 * and then its traffic to a 100.x address goes out over Wi-Fi or mobile data, where anyone on that network could
 * answer it (and some carriers hand out 100.64/10 addresses themselves, so the addresses alone cannot tell).
 */
final class Tailnet {
    /** A connection the client refuses to make; the message tells Stan what to change. */
    static final class Refused extends IOException {
        Refused(String message) {
            super(message);
        }
    }

    private Tailnet() {
    }

    /** 100.64.0.0/10 (Tailscale's IPv4 range) or fd7a:115c:a1e0::/48 (its IPv6 range). */
    static boolean isTailscale(InetAddress address) {
        byte[] bytes = address.getAddress();
        if (address instanceof Inet4Address) {
            return (bytes[0] & 0xff) == 100 && (bytes[1] & 0xc0) == 64;
        }
        if (address instanceof Inet6Address) {
            return (bytes[0] & 0xff) == 0xfd && (bytes[1] & 0xff) == 0x7a && (bytes[2] & 0xff) == 0x11
                    && (bytes[3] & 0xff) == 0x5c && (bytes[4] & 0xff) == 0xa1 && (bytes[5] & 0xff) == 0xe0;
        }
        return false;
    }

    /**
     * A host name or address Stan could mean as a server: a *.ts.net name or a Tailscale address, by its text alone
     * (no lookup: this runs on the main thread, for text any app can send in an intent).
     */
    static boolean looksLikeTailscale(String host) {
        String text = host.trim().toLowerCase(java.util.Locale.ROOT);
        if (text.endsWith(".ts.net") || text.endsWith(".ts.net.")) {
            return true;
        }
        return android.net.InetAddresses.isNumericAddress(text)
                && isTailscale(android.net.InetAddresses.parseNumericAddress(text));
    }

    /** The VPN network this app's traffic goes through, or null (Tailscale off, or this app outside its tunnel). */
    static Network vpnNetwork(Context context) {
        ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
        Network network = connectivity.getActiveNetwork();
        NetworkCapabilities capabilities = network == null ? null : connectivity.getNetworkCapabilities(network);
        return capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ? network : null;
    }

    static void connect(Context context, Socket socket, String host, int port, int timeoutMilliseconds)
            throws IOException {
        Network vpn = vpnNetwork(context);
        if (vpn == null) {
            throw new Refused("this app's traffic does not go through Tailscale: is Tailscale connected, and is Voxize "
                    + "Remote in its split tunneling (Tailscale → Settings → Split tunneling)?");
        }
        try {
            vpn.bindSocket(socket);
        } catch (IOException notAllowed) {
            throw new Refused("this app may not use the VPN: add Voxize Remote to Tailscale's split tunneling "
                    + "(Tailscale → Settings → Split tunneling)");
        }
        InetAddress target = null;
        try {
            // Resolved by the VPN's own DNS: MagicDNS names, and no answer from the local network's resolver.
            for (InetAddress candidate : vpn.getAllByName(host)) {
                if (isTailscale(candidate)) {
                    target = candidate;
                    break;
                }
            }
        } catch (UnknownHostException unknown) {
            throw new Refused("cannot find " + host + ": is Voxize Remote in Tailscale's split tunneling, and is "
                    + "Tailscale connected?");
        }
        if (target == null) {
            throw new Refused(host + " is not a Tailscale address; the client talks to Tailscale addresses only");
        }
        socket.connect(new InetSocketAddress(target, port), timeoutMilliseconds);
        if (!isTailscale(socket.getLocalAddress())) {
            socket.close();
            throw new Refused("this app's traffic does not go through Tailscale: add Voxize Remote to Tailscale's "
                    + "split tunneling (Tailscale → Settings → Split tunneling)");
        }
    }
}
