package dev.flemma.voxize.remote;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * The microphone foreground service. Android lets a background app record only from a foreground service of type
 * microphone that was started while the app was visible, so MainActivity or ArmActivity starts this, and it keeps
 * running (notification, overlay, connection) after the user goes back to Termux.
 *
 * The server owns the dictation: a tap only sends "toggle", and the microphone opens on "capture" and closes on
 * "halt". The overlay mirrors the server's "status" messages.
 */
public final class VoxService extends Service
        implements Link.Listener, Capture.Listener, Overlay.Listener, ForegroundWatcher.Listener {
    static final String ACTION_ARM = "dev.flemma.voxize.remote.ARM";
    static final String ACTION_TOGGLE = "dev.flemma.voxize.remote.TOGGLE";
    static final String ACTION_QUIT = "dev.flemma.voxize.remote.QUIT";
    static final String PREFERENCES = "voxize-remote";
    // Written by MainActivity once a pairing is confirmed on both screens.
    static final String PREFERENCE_DEVICE_ID = "device_id";
    static final String PREFERENCE_SECRET = "secret";
    static final String PREFERENCE_SERVER = "server";
    // No server until `cc remote setup` provides one (MainActivity's first-run hand-off) or Stan types one.
    static final String DEFAULT_HOST = "";
    static final int DEFAULT_PORT = 7223;

    private static final String TAG = "VoxizeService";
    private static final String CHANNEL = "voxize-remote";
    private static final int NOTIFICATION_ID = 1;
    private static final long DONE_LINGER_MILLISECONDS = 6000;
    private static final long TIMER_TICK_MILLISECONDS = 250;
    // With no Termux session and no dictation for this long, the client disarms: the microphone service, the
    // connection and, on the server, the process that only runs while a client is connected. Counted in uptime, which
    // stops while the phone sleeps: a connection that dropped during sleep gets its chance to return at wake.
    private static final long IDLE_DISARM_MILLISECONDS = 15 * 60 * 1000L;
    private static final long IDLE_CHECK_MILLISECONDS = 60 * 1000L;

    /** What MainActivity shows; written on the main thread only. */
    static volatile String summary = "Not running.";
    // A `capture` more than this long after the last tap is refused: only a tap on this client may start a recording.
    private static final long CAPTURE_AFTER_TAP_MILLISECONDS = 10_000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile Link link;
    private Capture capture;
    private Overlay overlay;
    private ForegroundWatcher foreground;
    // Termux is the app in front (always true without Usage access), and the server says Termux has a session open.
    private boolean termuxInFront = true;
    private boolean session = true;
    private long usefulAt;
    private final Runnable idleCheck = new Runnable() {
        @Override
        public void run() {
            if (!armed) {
                return;
            }
            boolean dictating = !"idle".equals(phase) && !"done".equals(phase) && !"cancelled".equals(phase)
                    && !"error".equals(phase);
            // Without a connection nothing is useful: a server that stays unreachable disarms the client too.
            if (capture.running() || connected && (session || dictating)) {
                usefulAt = SystemClock.uptimeMillis();
            }
            if (SystemClock.uptimeMillis() - usefulAt > IDLE_DISARM_MILLISECONDS) {
                Log.i(TAG, "no session and no dictation for a while; disarming");
                shutDown();
                return;
            }
            main.postDelayed(this, IDLE_CHECK_MILLISECONDS);
        }
    };
    private PowerManager.WakeLock wakeLock;
    private boolean armed;
    // When this client last asked to start a recording: a tap on the floating button or the notification's Record.
    private long lastToggleAt = Long.MIN_VALUE / 2;
    // The app's own screen is open: the floating button and bubble would cover its buttons.
    private boolean appInFront;
    /** The running service, for MainActivity's onResume and onPause (main thread only). */
    static VoxService current;
    /** MainActivity is open, even before a service exists to tell (main thread only). */
    static boolean mainScreenOpen;
    /** For MainActivity's checklist: armed, connected to a server that proved itself, and the last problem seen. */
    static volatile boolean armedNow;
    static volatile boolean connectedNow;
    static volatile String problemNow = "";
    // host:port:device id of the running link; arming again with the same one keeps it.
    private String linkKey;
    private boolean connected;
    private String connectionNote = "connecting";
    private String phase = "idle";
    private String text = "";
    private String detail = "";
    private String notifiedLine;
    private int audioBlocks;
    private float progress = OrbView.NO_PROGRESS;
    private long recordingSince;
    private final Runnable timerTick = new Runnable() {
        @Override
        public void run() {
            long seconds = (SystemClock.elapsedRealtime() - recordingSince) / 1000;
            overlay.timer(String.format(java.util.Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60));
            main.postDelayed(this, TIMER_TICK_MILLISECONDS);
        }
    };

    static Intent intent(Context context, String action) {
        return new Intent(context, VoxService.class).setAction(action);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationChannel channel = new NotificationChannel(CHANNEL, "Voxize Remote", NotificationManager.IMPORTANCE_LOW);
        channel.setShowBadge(false);
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
        capture = new Capture(this);
        overlay = new Overlay(this, this);
        foreground = new ForegroundWatcher(this, this);
        wakeLock = getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "voxize:capture");
        wakeLock.setReferenceCounted(false);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null && intent.getAction() != null ? intent.getAction() : ACTION_ARM;
        if (ACTION_QUIT.equals(action)) {
            shutDown();
            return START_NOT_STICKY;
        }
        if (ACTION_ARM.equals(action)) {
            arm();
        } else if (ACTION_TOGGLE.equals(action)) {
            if (armed) {
                onTap();
            } else {
                // Not armed (killed and restarted from a notification): the microphone cannot open from here.
                stopSelf();
            }
        }
        // Never restarted by the system: from the background it could not take the microphone anyway.
        return START_NOT_STICKY;
    }

    private void arm() {
        try {
            startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
        } catch (RuntimeException refused) {
            // SecurityException without RECORD_AUDIO; ForegroundServiceStartNotAllowedException from the background.
            Log.e(TAG, "could not enter the foreground", refused);
            summary = "Android refused the microphone service: " + refused.getMessage();
            ArmActivity.release();
            stopSelf();
            return;
        }
        ArmActivity.release();
        armed = true;
        SharedPreferences preferences = getSharedPreferences(PREFERENCES, MODE_PRIVATE);
        String host = preferences.getString("host", DEFAULT_HOST);
        if (host == null || host.isEmpty()) {
            host = DEFAULT_HOST;
        }
        int port = preferences.getInt("port", DEFAULT_PORT);
        String deviceId = preferences.getString(PREFERENCE_DEVICE_ID, null);
        byte[] secret = Pairing.unhex(preferences.getString(PREFERENCE_SECRET, null), 32);
        String key = host + ":" + port + ":" + deviceId;
        // Arming again after a new address or a new pairing (MainActivity) reconnects; otherwise it keeps the link.
        if (link == null || !key.equals(linkKey)) {
            if (link != null) {
                capture.stop();
                link.stop();
                link = null;
            }
            connected = false;
            linkKey = key;
            if (deviceId == null || secret == null) {
                connectionNote = "not paired: open Voxize Remote and pair with the server";
                problemNow = connectionNote;
            } else {
                connectionNote = "connecting to " + host + ":" + port;
                link = new Link(this, host, port, deviceId, secret, this);
                link.start();
            }
        } else if (!connected) {
            link.retryNow();
        }
        current = this;
        armedNow = true;
        appInFront = mainScreenOpen;
        usefulAt = SystemClock.uptimeMillis();
        main.removeCallbacks(idleCheck);
        main.postDelayed(idleCheck, IDLE_CHECK_MILLISECONDS);
        foreground.start();
        updateOverlay();
        refresh();
    }

    /** MainActivity is in front (true) or left (false): hide the floating button meanwhile. */
    void setAppInFront(boolean inFront) {
        appInFront = inFront;
        updateOverlay();
    }

    @Override
    public void onTermuxInFront(boolean inFront) {
        termuxInFront = inFront;
        updateOverlay();
    }

    /**
     * The floating button shows while Termux is in front with a session open: that is where it pastes. With no
     * connection it shows too, so the trouble is visible where Stan expects the button. A recording keeps it wherever
     * Stan goes, so the button that stops it never disappears. Never over this app's screen.
     */
    private void updateOverlay() {
        boolean recording = connected && ("starting".equals(phase) || "recording".equals(phase));
        boolean wanted = armed && !appInFront && (recording || termuxInFront && (!connected || session));
        if (!wanted) {
            overlay.hide();
            return;
        }
        if (!overlay.shown()) {
            if (overlay.show()) {
                refresh();
            } else {
                Log.i(TAG, "no overlay permission; the notification's Record action still works");
            }
        }
    }

    private void shutDown() {
        armed = false;
        armedNow = false;
        connectedNow = false;
        if (current == this) {
            current = null;
        }
        capture.stop();
        if (link != null) {
            link.stop();
            link = null;
        }
        foreground.stop();
        main.removeCallbacks(idleCheck);
        overlay.hide();
        wakeLock.release();
        summary = "Not running.";
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    @Override
    public void onDestroy() {
        if (armed) {
            shutDown();
        }
        super.onDestroy();
    }

    // Overlay.Listener (main thread).

    @Override
    public void onTap() {
        switch (phase) {
            case "done":
            case "cancelled":
            case "error":
                // A result or a complaint on the button: the tap puts it away; the next tap records.
                dismiss();
                return;
            case "finishing":
            case "processing":
                // Voxize is working; a long press cancels.
                return;
            default:
                break;
        }
        Link active = link;
        if (active == null || !active.connected()) {
            // Nothing to record into: the checklist says what is missing (pairing, Tailscale) and how to fix it.
            // Allowed from here because the floating button is a visible overlay window.
            startActivity(new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return;
        }
        lastToggleAt = SystemClock.elapsedRealtime();
        active.sendJson(Link.json("toggle"));
    }

    private void dismiss() {
        phase = "idle";
        text = "";
        detail = "";
        progress = OrbView.NO_PROGRESS;
        refresh();
    }

    @Override
    public void onLongPress() {
        if (link != null) {
            link.sendJson(Link.json("cancel"));
        }
    }

    // Link.Listener (link thread).

    @Override
    public void onConnected() {
        main.post(() -> {
            if (!armed) {
                return;
            }
            connected = true;
            connectedNow = true;
            problemNow = "";
            connectionNote = "connected";
            detail = "";
            updateOverlay();
            refresh();
        });
    }

    @Override
    public void onDisconnected(final String reason) {
        main.post(() -> {
            if (!armed) {
                return;
            }
            connected = false;
            connectedNow = false;
            problemNow = reason;
            connectionNote = reason;
            // The server ends a dictation whose client went away; nothing left to send it.
            capture.stop();
            updateOverlay();
            refresh();
        });
    }

    @Override
    public void onMessage(final JSONObject message) {
        main.post(() -> handle(message));
    }

    private void handle(JSONObject message) {
        // A message queued before Quit must not open the microphone of a service that is no longer in the foreground.
        if (!armed) {
            return;
        }
        String type = message.optString("type");
        switch (type) {
            case "capture":
                // The server proved itself, but its word alone does not open the microphone: someone who copied
                // the pairing secret could play the server. Only a tap here in the last few seconds does.
                if (SystemClock.elapsedRealtime() - lastToggleAt > CAPTURE_AFTER_TAP_MILLISECONDS) {
                    Log.w(TAG, "refused a capture that no tap on this client asked for");
                    onCaptured("no tap on the client asked for this recording");
                    break;
                }
                lastToggleAt = Long.MIN_VALUE / 2;
                audioBlocks = 0;
                wakeLock.acquire(15 * 60 * 1000L);
                capture.start();
                break;
            case "halt":
                capture.stop();
                break;
            case "status":
                phase = message.optString("phase", "idle");
                text = message.optString("text", "");
                detail = message.optString("detail", "");
                session = message.optBoolean("session", true);
                updateOverlay();
                if ("finishing".equals(phase) || "processing".equals(phase)) {
                    // A number is Voxize's estimate; null means it has none yet, so the ring spins.
                    progress = message.has("progress") && !message.isNull("progress")
                            ? (float) message.optDouble("progress", 0) : OrbView.INDETERMINATE;
                } else {
                    progress = OrbView.NO_PROGRESS;
                }
                if ("done".equals(phase) || "cancelled".equals(phase)) {
                    final String finished = phase;
                    main.postDelayed(() -> {
                        if (finished.equals(phase)) {
                            dismiss();
                        }
                    }, DONE_LINGER_MILLISECONDS);
                }
                refresh();
                break;
            case "error":
                detail = message.optString("message", "error");
                refresh();
                break;
            default:
                break;
        }
    }

    // Capture.Listener (capture thread).

    @Override
    public void onCapturing(int deviceRate, String source) {
        Link current = link;
        if (current == null) {
            return;
        }
        JSONObject message = Link.json("capturing");
        try {
            message.put("rate", deviceRate);
            message.put("source", source);
        } catch (JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
        current.sendJson(message);
        main.post(() -> {
            recordingSince = SystemClock.elapsedRealtime();
            main.removeCallbacks(timerTick);
            timerTick.run();
        });
    }

    @Override
    public void onAudio(byte[] pcm, final float level) {
        Link current = link;
        if (current != null) {
            current.sendAudio(pcm);
        }
        if (++audioBlocks % 3 == 0) {
            main.post(() -> overlay.level(level));
        }
    }

    @Override
    public void onCaptured(final String error) {
        Link current = link;
        if (current != null) {
            if (error == null) {
                current.sendJson(Link.json("captured"));
            } else {
                JSONObject message = Link.json("mic_error");
                try {
                    message.put("message", error);
                } catch (JSONException impossible) {
                    throw new IllegalStateException(impossible);
                }
                current.sendJson(message);
            }
        }
        main.post(() -> {
            wakeLock.release();
            main.removeCallbacks(timerTick);
            overlay.timer(null);
            overlay.level(0f);
            if (error != null) {
                detail = "microphone: " + error;
                refresh();
            }
        });
    }

    // Presentation (main thread).

    private void refresh() {
        String shown = text;
        if (!detail.isEmpty() && !"recording".equals(phase)) {
            shown = text.isEmpty() ? detail : text + "\n— " + detail;
        } else if (!connected && text.isEmpty()) {
            shown = "Voxize: " + connectionNote;
        }
        overlay.render(connected ? phase : "disconnected", shown, connected, progress);
        String line = connected ? phase + (detail.isEmpty() ? "" : " — " + detail) : connectionNote;
        summary = (armed ? "Running: " : "Not running: ") + line
                + (android.provider.Settings.canDrawOverlays(this) ? ""
                        : "\nNo floating button: allow \"Display over other apps\" for it.");
        String notified = notificationText();
        if (armed && !notified.equals(notifiedLine)) {
            notifiedLine = notified;
            getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, notification());
        }
    }

    /** The phase in plain words. The notification never names the session or shows what was said. */
    private String notificationText() {
        if (!connected) {
            return link == null ? "Not paired" : "Not connected";
        }
        switch (phase) {
            case "starting":
            case "recording":
                return "Recording";
            case "finishing":
            case "processing":
                return "Transcribing";
            case "done":
                return "Pasted";
            case "cancelled":
                return "Cancelled";
            case "error":
                return "Something went wrong; the button says what";
            default:
                return "Ready";
        }
    }

    private Notification notification() {
        int immutable = PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT;
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), immutable);
        PendingIntent toggle = PendingIntent.getService(this, 1, intent(this, ACTION_TOGGLE), immutable);
        PendingIntent quit = PendingIntent.getService(this, 2, intent(this, ACTION_QUIT), immutable);
        boolean recording = "recording".equals(phase) || "starting".equals(phase);
        String line = notifiedLine != null ? notifiedLine : notificationText();
        // On the lock screen: the app's name and nothing else.
        Notification lockScreen = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_mic)
                .setContentTitle("Voxize Remote")
                .build();
        Notification.Builder builder = new Notification.Builder(this, CHANNEL);
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE);
        }
        return builder
                .setSmallIcon(R.drawable.ic_mic)
                .setContentTitle("Voxize Remote")
                .setContentText(line)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(lockScreen)
                .setContentIntent(open)
                .addAction(new Notification.Action.Builder(
                        Icon.createWithResource(this, recording ? R.drawable.ic_stop : R.drawable.ic_mic),
                        recording ? "Stop" : "Record", toggle).build())
                .addAction(new Notification.Action.Builder(
                        Icon.createWithResource(this, R.drawable.ic_close),
                        "Quit", quit).build())
                .build();
    }
}
