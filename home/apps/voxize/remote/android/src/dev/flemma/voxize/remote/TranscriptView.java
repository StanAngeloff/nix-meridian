package dev.flemma.voxize.remote;

import android.content.Context;
import android.util.TypedValue;
import android.view.View;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * The text in the bubble: at most a few lines tall, kept scrolled to the newest words, with older lines fading out
 * toward the top edge instead of being cut. A finger can scroll back up.
 *
 * Its width is fixed and its scroll position is worked out from the fixed maximum height, never from its current
 * height: the overlay window resizes a frame after the content changes, and scrolling against the old size made the
 * text jump up a line and fall back while the bubble grew.
 */
final class TranscriptView extends ScrollView {
    private final TextView text;
    private final int maximumHeight;

    TranscriptView(Context context, int maximumWidth, int visibleLines) {
        super(context);
        text = new TextView(context);
        text.setTextColor(0xFF1F1F1F);
        text.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        text.setLineSpacing(0, 1.1f);
        text.setWidth(maximumWidth);
        addView(text);
        maximumHeight = Math.round(text.getLineHeight() * visibleLines);
        text.addOnLayoutChangeListener((view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> settle());
        setVerticalScrollBarEnabled(false);
        setOverScrollMode(View.OVER_SCROLL_NEVER);
        setVerticalFadingEdgeEnabled(true);
        setFadingEdgeLength(Math.round(text.getLineHeight() * 1.5f));
    }

    TextView text() {
        return text;
    }

    /** Shows the text; once it overflows, the view glides to its end, where the newest words are. */
    void setText(CharSequence value) {
        if (!value.toString().contentEquals(text.getText())) {
            text.setText(value);
        }
    }

    private void settle() {
        int overflow = text.getHeight() - maximumHeight;
        if (overflow <= 0) {
            if (getScrollY() != 0) {
                scrollTo(0, 0);
            }
            return;
        }
        boolean full = getHeight() - getPaddingTop() - getPaddingBottom() >= maximumHeight;
        if (full) {
            smoothScrollTo(0, overflow);
        } else {
            // Still growing to full height: jump, the window is about to catch up.
            scrollTo(0, overflow);
        }
    }

    /** No fade at the bottom: the newest line is always whole. */
    @Override
    protected float getBottomFadingEdgeStrength() {
        return 0f;
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int limit = maximumHeight + getPaddingTop() + getPaddingBottom();
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(limit, MeasureSpec.AT_MOST));
    }
}
