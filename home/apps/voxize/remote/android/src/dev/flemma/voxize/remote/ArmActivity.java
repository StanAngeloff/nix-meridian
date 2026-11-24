package dev.flemma.voxize.remote;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;

/**
 * A see-through activity for Termux: {@code am start -n dev.flemma.voxize.remote/.ArmActivity}. Android grants a
 * microphone foreground service only to an app the user can see, so this stays on screen until VoxService reports it
 * is in the foreground (or refused), then closes and Termux is back in front.
 */
public final class ArmActivity extends Activity {
    private static ArmActivity showing;

    /** Called by VoxService on the main thread once startForeground returned or failed. */
    static void release() {
        if (showing != null) {
            showing.finish();
            showing = null;
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            // The permission prompt needs the real screen.
            startActivity(new Intent(this, MainActivity.class));
            finish();
            return;
        }
        showing = this;
        startForegroundService(VoxService.intent(this, VoxService.ACTION_ARM));
        // It covers Termux and takes its touches: never for long, whatever happens to the service.
        getWindow().getDecorView().postDelayed(this::finish, 3000);
    }

    @Override
    protected void onDestroy() {
        if (showing == this) {
            showing = null;
        }
        super.onDestroy();
    }
}
