package dev.flemma.voxize.remote;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.PixelFormat;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.widget.FrameLayout;

/**
 * A floating microphone button over every app (Termux included) and a strip of text above it. Neither takes focus,
 * so the keyboard stays with the app below. VoxService decides what a tap does; long press cancels, drag moves, a tap
 * on the text hides it.
 *
 * The button and the text are two windows. The button's window has a fixed size and moves only when dragged; the
 * text's window resizes with every word and follows the button. In one window, each resize moved the button.
 */
final class Overlay {
    interface Listener {
        void onTap();
        void onLongPress();
    }

    private static final int LONG_PRESS_MILLISECONDS = 600;
    /** Transparent room around the text bubble, in dp, so its shadow is not cut off by its window. */
    private static final int SHADOW_ROOM = 8;
    /** The bubble's tail, in dp. */
    private static final int TAIL_WIDTH = 16;
    private static final int TAIL_HEIGHT = 8;
    private static final int VISIBLE_LINES = 5;
    /** Where the button rests until it is dragged: about the top of a client keyboard, as a share of the screen. */
    private static final float DEFAULT_HEIGHT_SHARE = 0.37f;
    private static final String PREFERENCE_X = "orb_x";
    private static final String PREFERENCE_Y = "orb_y";

    private final Context context;
    private final WindowManager windows;
    private final Listener listener;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private OrbView orb;
    // The text's window: a transparent box with room for the bubble's shadow, and the bubble in it.
    private FrameLayout labelBox;
    private TranscriptView label;
    private WindowManager.LayoutParams orbLayout;
    private WindowManager.LayoutParams labelLayout;

    Overlay(Context context, Listener listener) {
        this.context = context;
        this.windows = context.getSystemService(WindowManager.class);
        this.listener = listener;
    }

    boolean shown() {
        return orb != null;
    }

    private static WindowManager.LayoutParams floating(int width, int height) {
        WindowManager.LayoutParams layout = new WindowManager.LayoutParams(
                width,
                height,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT);
        // x counts from the right edge, y from the bottom.
        layout.gravity = Gravity.BOTTOM | Gravity.RIGHT;
        return layout;
    }

    /** Shows the button when the overlay permission is granted; false otherwise. */
    boolean show() {
        if (orb != null) {
            return true;
        }
        if (!Settings.canDrawOverlays(context)) {
            return false;
        }
        OrbView newOrb = new OrbView(context);
        newOrb.setOnTouchListener(new Drag());
        orbLayout = floating(newOrb.sizePixels(), newOrb.sizePixels());
        // Android does not tell an overlay where another app's keyboard is, so the button starts at a typical
        // keyboard's top and stays wherever it was last dragged.
        SharedPreferences preferences = context.getSharedPreferences(VoxService.PREFERENCES, Context.MODE_PRIVATE);
        orbLayout.x = preferences.getInt(PREFERENCE_X, dp(12));
        orbLayout.y = preferences.getInt(PREFERENCE_Y,
                Math.round(context.getResources().getDisplayMetrics().heightPixels * DEFAULT_HEIGHT_SHARE));
        clampOrb();

        // A light, nearly opaque bubble with dark text: it stands apart from a dark terminal.
        TranscriptView newLabel = new TranscriptView(context, dp(280), VISIBLE_LINES);
        newLabel.setPadding(dp(12), dp(8), dp(12), dp(8 + TAIL_HEIGHT));
        // The bubble's right edge lines up with the circle's, so the circle's centre is one radius in from it.
        newLabel.setBackground(new BubbleDrawable(0xF5FAFAFA, dp(14), dp(TAIL_WIDTH), dp(TAIL_HEIGHT),
                newOrb.circleRadiusPixels()));
        newLabel.setElevation(dp(4));
        FrameLayout newBox = new FrameLayout(context);
        newBox.setPadding(dp(SHADOW_ROOM), dp(SHADOW_ROOM), dp(SHADOW_ROOM), dp(SHADOW_ROOM));
        newBox.setClipToPadding(false);
        newBox.addView(newLabel);
        newBox.setVisibility(View.GONE);
        newLabel.text().setOnClickListener(view -> newBox.setVisibility(View.GONE));
        labelLayout = floating(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT);
        followOrb(newOrb);

        try {
            windows.addView(newOrb, orbLayout);
        } catch (RuntimeException refused) {
            // The grant was revoked between the check and here.
            return false;
        }
        try {
            windows.addView(newBox, labelLayout);
        } catch (RuntimeException refused) {
            removeQuietly(newOrb);
            return false;
        }
        orb = newOrb;
        labelBox = newBox;
        label = newLabel;
        render("disconnected", "", false, OrbView.NO_PROGRESS);
        return true;
    }

    void hide() {
        if (orb != null) {
            removeQuietly(orb);
            removeQuietly(labelBox);
            orb = null;
            labelBox = null;
            label = null;
        }
    }

    private void removeQuietly(View view) {
        try {
            windows.removeView(view);
        } catch (RuntimeException alreadyGone) {
            // The system removed it already.
        }
    }

    /** The bubble sits just above the circle, its right edge on the circle's. */
    private void followOrb(OrbView view) {
        int margin = view.marginPixels();
        labelLayout.x = orbLayout.x + margin - dp(SHADOW_ROOM);
        labelLayout.y = orbLayout.y + orbLayout.height - margin + dp(3) - dp(SHADOW_ROOM);
    }

    /**
     * The button's look for a phase (the server's, or "disconnected"), the text above it and the progress ring
     * (OrbView.NO_PROGRESS, OrbView.INDETERMINATE or a fraction).
     */
    void render(String phase, String text, boolean connected, float progress) {
        if (orb == null) {
            return;
        }
        int color;
        int iconId;
        switch (phase) {
            case "starting":
            case "recording":
                color = 0xFFE53935;
                iconId = R.drawable.ic_stop;
                break;
            case "finishing":
            case "processing":
                color = 0xFFF57C00;
                iconId = R.drawable.ic_edit_note;
                break;
            case "done":
                color = 0xFF43A047;
                iconId = R.drawable.ic_check;
                break;
            case "cancelled":
                color = 0xFF546E7A;
                iconId = R.drawable.ic_close;
                break;
            case "error":
                color = 0xFF8D6E63;
                iconId = R.drawable.ic_priority_high;
                break;
            case "disconnected":
                color = 0xFF455A64;
                iconId = R.drawable.ic_mic_off;
                break;
            default:
                color = 0xFF37474F;
                iconId = R.drawable.ic_mic;
                break;
        }
        orb.show(color, context.getDrawable(iconId));
        orb.setAlpha(connected ? 1f : 0.7f);
        orb.setProgress(progress);
        if (text == null || text.isEmpty()) {
            labelBox.setVisibility(View.GONE);
        } else {
            label.setText(text);
            labelBox.setVisibility(View.VISIBLE);
        }
    }

    /** Keeps the button on screen (a saved position from a taller screen, or a drag past the edge). */
    private void clampOrb() {
        int maximumX = context.getResources().getDisplayMetrics().widthPixels - orbLayout.width;
        int maximumY = context.getResources().getDisplayMetrics().heightPixels - orbLayout.height;
        orbLayout.x = Math.max(0, Math.min(maximumX, orbLayout.x));
        orbLayout.y = Math.max(0, Math.min(maximumY, orbLayout.y));
    }

    /** Recording loudness, 0 to 1: a halo around the button. */
    void level(float level) {
        if (orb != null) {
            orb.setLevel(level);
        }
    }

    /** The time recorded so far under the icon ("0:12"), or null. */
    void timer(String text) {
        if (orb != null) {
            orb.setTimer(text);
        }
    }

    private int dp(int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    private final class Drag implements View.OnTouchListener {
        private final int slop = ViewConfiguration.get(context).getScaledTouchSlop();
        private float downX;
        private float downY;
        private int startX;
        private int startY;
        private boolean moved;
        private boolean longPressed;
        private final Runnable longPress = () -> {
            longPressed = true;
            listener.onLongPress();
        };

        @Override
        public boolean onTouch(View view, MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = event.getRawX();
                    downY = event.getRawY();
                    startX = orbLayout.x;
                    startY = orbLayout.y;
                    moved = false;
                    longPressed = false;
                    handler.postDelayed(longPress, LONG_PRESS_MILLISECONDS);
                    return true;
                case MotionEvent.ACTION_MOVE:
                    float dx = event.getRawX() - downX;
                    float dy = event.getRawY() - downY;
                    if (!moved && Math.hypot(dx, dy) > slop) {
                        moved = true;
                        handler.removeCallbacks(longPress);
                    }
                    if (moved && orb != null) {
                        orbLayout.x = startX - Math.round(dx);
                        orbLayout.y = startY - Math.round(dy);
                        clampOrb();
                        windows.updateViewLayout(orb, orbLayout);
                        followOrb(orb);
                        windows.updateViewLayout(labelBox, labelLayout);
                    }
                    return true;
                case MotionEvent.ACTION_UP:
                    handler.removeCallbacks(longPress);
                    if (moved) {
                        context.getSharedPreferences(VoxService.PREFERENCES, Context.MODE_PRIVATE).edit()
                                .putInt(PREFERENCE_X, orbLayout.x).putInt(PREFERENCE_Y, orbLayout.y).apply();
                    }
                    if (!moved && !longPressed) {
                        view.performClick();
                        listener.onTap();
                    }
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    handler.removeCallbacks(longPress);
                    return true;
                default:
                    return false;
            }
        }
    }
}
