package dev.flemma.voxize.remote;

import android.app.AppOpsManager;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.Process;

/**
 * Whether Termux is the app in front, from Usage access (`cc remote setup` grants it over adb). Termux does not report
 * focus to tmux, so this is the only way to show the floating button just while Termux is in front.
 *
 * Without Usage access every answer is "in front": the button then shows as it did before, everywhere.
 */
final class ForegroundWatcher {
    interface Listener {
        void onTermuxInFront(boolean inFront);
    }

    static final String TERMUX = "com.termux";
    private static final long POLL_MILLISECONDS = 700;
    // With the screen off nothing is in front to look at; the events since are read once it is back on.
    private static final long SCREEN_OFF_POLL_MILLISECONDS = 5000;
    // On start, how far back to look for the app last brought to front.
    private static final long FIRST_LOOK_BACK_MILLISECONDS = 30 * 60 * 1000L;

    private final Context context;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final UsageStatsManager usage;
    private final PowerManager power;
    private long queriedUntil;
    private String frontPackage;
    private boolean running;
    private Boolean reported;

    ForegroundWatcher(Context context, Listener listener) {
        this.context = context;
        this.listener = listener;
        this.usage = context.getSystemService(UsageStatsManager.class);
        this.power = context.getSystemService(PowerManager.class);
    }

    boolean permitted() {
        AppOpsManager appOps = context.getSystemService(AppOpsManager.class);
        int mode = appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.getPackageName());
        return mode == AppOpsManager.MODE_ALLOWED;
    }

    void start() {
        if (running) {
            return;
        }
        running = true;
        queriedUntil = System.currentTimeMillis() - FIRST_LOOK_BACK_MILLISECONDS;
        frontPackage = null;
        reported = null;
        main.post(this::poll);
    }

    void stop() {
        running = false;
        main.removeCallbacksAndMessages(null);
    }

    private void poll() {
        if (!running) {
            return;
        }
        if (!power.isInteractive()) {
            main.postDelayed(this::poll, SCREEN_OFF_POLL_MILLISECONDS);
            return;
        }
        boolean inFront;
        if (permitted()) {
            long now = System.currentTimeMillis();
            UsageEvents events = usage.queryEvents(queriedUntil, now);
            UsageEvents.Event event = new UsageEvents.Event();
            while (events != null && events.hasNextEvent()) {
                events.getNextEvent(event);
                if (event.getEventType() == UsageEvents.Event.ACTIVITY_RESUMED) {
                    frontPackage = event.getPackageName();
                }
            }
            queriedUntil = now;
            inFront = TERMUX.equals(frontPackage);
        } else {
            inFront = true;
        }
        if (reported == null || reported != inFront) {
            reported = inFront;
            listener.onTermuxInFront(inFront);
        }
        main.postDelayed(this::poll, POLL_MILLISECONDS);
    }
}
