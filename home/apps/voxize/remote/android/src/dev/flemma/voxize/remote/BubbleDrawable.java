package dev.flemma.voxize.remote;

import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;

/**
 * A speech bubble: a rounded rectangle with a tail along its bottom edge, pointing down at the button. The tail takes
 * the bottom {@code tailHeight} pixels of the bounds, so the view holding it pads its bottom by as much. The outline
 * is the same shape, so the shadow follows the tail too.
 */
final class BubbleDrawable extends Drawable {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();
    private final float radius;
    private final float tailWidth;
    private final float tailHeight;
    private final float tailFromRight;

    /** tailFromRight: where the tail's tip sits, measured from the right edge (the button's centre). */
    BubbleDrawable(int color, float radius, float tailWidth, float tailHeight, float tailFromRight) {
        paint.setColor(color);
        this.radius = radius;
        this.tailWidth = tailWidth;
        this.tailHeight = tailHeight;
        this.tailFromRight = tailFromRight;
    }

    @Override
    protected void onBoundsChange(Rect bounds) {
        path.reset();
        RectF body = new RectF(bounds.left, bounds.top, bounds.right, bounds.bottom - tailHeight);
        path.addRoundRect(body, radius, radius, Path.Direction.CW);
        float half = tailWidth / 2;
        // Keep the tail off the rounded corners when the bubble is narrow.
        float tipX = Math.max(body.left + radius + half, Math.min(body.right - radius - half, bounds.right - tailFromRight));
        Path tail = new Path();
        tail.moveTo(tipX - half, body.bottom - 1);
        tail.lineTo(tipX, bounds.bottom);
        tail.lineTo(tipX + half, body.bottom - 1);
        tail.close();
        path.op(tail, Path.Op.UNION);
    }

    @Override
    public void draw(Canvas canvas) {
        canvas.drawPath(path, paint);
    }

    @Override
    public void getOutline(Outline outline) {
        outline.setPath(path);
    }

    @Override
    public void setAlpha(int alpha) {
        paint.setAlpha(alpha);
        invalidateSelf();
    }

    @Override
    public void setColorFilter(ColorFilter colorFilter) {
        paint.setColorFilter(colorFilter);
        invalidateSelf();
    }

    @Override
    public int getOpacity() {
        return PixelFormat.TRANSLUCENT;
    }
}
