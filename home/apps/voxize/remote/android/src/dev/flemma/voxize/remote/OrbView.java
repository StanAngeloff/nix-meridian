package dev.flemma.voxize.remote;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.os.SystemClock;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewOutlineProvider;

/**
 * The floating button: a filled circle with an icon, optionally the time recorded under the icon, a halo that follows
 * the voice level and a ring around the circle for Voxize's progress. Everything is drawn inside the view's own
 * bounds (the circle leaves room for the halo and the ring), so nothing is clipped by the overlay window.
 */
final class OrbView extends View {
    /** No ring. */
    static final float NO_PROGRESS = Float.NaN;
    /** A spinning ring: working, no estimate yet. */
    static final float INDETERMINATE = -1f;

    private static final long SPIN_MILLISECONDS = 1100;

    private final float circleRadius;
    private final float ringRadius;
    private final float ringWidth;
    private final float iconSize;
    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint halo = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint arc = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint timer = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF ringBounds = new RectF();

    private Drawable icon;
    private String timerText;
    private float level;
    private float progress = NO_PROGRESS;

    OrbView(Context context) {
        super(context);
        circleRadius = dp(28);
        ringWidth = dp(3);
        ringRadius = circleRadius + dp(5);
        iconSize = dp(28);
        halo.setStyle(Paint.Style.FILL);
        track.setStyle(Paint.Style.STROKE);
        track.setStrokeWidth(ringWidth);
        track.setColor(0x40FFFFFF);
        arc.setStyle(Paint.Style.STROKE);
        arc.setStrokeWidth(ringWidth);
        arc.setStrokeCap(Paint.Cap.ROUND);
        arc.setColor(Color.WHITE);
        timer.setColor(Color.WHITE);
        timer.setTextAlign(Paint.Align.CENTER);
        timer.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        timer.setTextSize(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 11,
                context.getResources().getDisplayMetrics()));
        // The shadow follows the circle, not the square view.
        setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
                int centerX = view.getWidth() / 2;
                int centerY = view.getHeight() / 2;
                int radius = Math.round(circleRadius);
                outline.setOval(centerX - radius, centerY - radius, centerX + radius, centerY + radius);
            }
        });
        setElevation(dp(6));
    }

    int sizePixels() {
        return Math.round(2 * (ringRadius + ringWidth));
    }

    int circleRadiusPixels() {
        return Math.round(circleRadius);
    }

    /** The room left around the circle for the halo and the ring. */
    int marginPixels() {
        return Math.round(ringRadius + ringWidth - circleRadius);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        setMeasuredDimension(sizePixels(), sizePixels());
    }

    /** Colour and icon of the circle. */
    void show(int color, Drawable newIcon) {
        fill.setColor(color);
        halo.setColor((color & 0x00FFFFFF) | 0x55000000);
        icon = newIcon;
        invalidate();
    }

    /** "0:12" under the icon while recording; null for none. */
    void setTimer(String text) {
        if (text == null ? timerText != null : !text.equals(timerText)) {
            timerText = text;
            invalidate();
        }
    }

    /** Voice level, 0 to 1. */
    void setLevel(float value) {
        level = Math.max(0f, Math.min(1f, value));
        invalidate();
    }

    /** NO_PROGRESS, INDETERMINATE, or a fraction from 0 to 1. */
    void setProgress(float value) {
        progress = value;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        float centerX = getWidth() / 2f;
        float centerY = getHeight() / 2f;
        if (level > 0f) {
            canvas.drawCircle(centerX, centerY, circleRadius + level * (ringRadius + ringWidth - circleRadius), halo);
        }
        canvas.drawCircle(centerX, centerY, circleRadius, fill);

        if (icon != null) {
            int half = Math.round(iconSize / 2);
            int iconCenterY = Math.round(centerY - (timerText != null ? dp(6) : 0));
            icon.setBounds(Math.round(centerX) - half, iconCenterY - half, Math.round(centerX) + half, iconCenterY + half);
            icon.draw(canvas);
        }
        if (timerText != null) {
            canvas.drawText(timerText, centerX, centerY + dp(18), timer);
        }

        if (!Float.isNaN(progress)) {
            ringBounds.set(centerX - ringRadius, centerY - ringRadius, centerX + ringRadius, centerY + ringRadius);
            canvas.drawOval(ringBounds, track);
            if (progress < 0f) {
                float turn = (SystemClock.uptimeMillis() % SPIN_MILLISECONDS) / (float) SPIN_MILLISECONDS;
                canvas.drawArc(ringBounds, turn * 360f - 90f, 90f, false, arc);
                postInvalidateOnAnimation();
            } else {
                canvas.drawArc(ringBounds, -90f, 360f * Math.min(1f, progress), false, arc);
            }
        }
    }

    private float dp(float value) {
        return value * getResources().getDisplayMetrics().density;
    }
}
