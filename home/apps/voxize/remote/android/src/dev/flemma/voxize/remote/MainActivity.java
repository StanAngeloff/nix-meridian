package dev.flemma.voxize.remote;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/**
 * The client's one screen: the server it pairs with, and a checklist of everything the floating button needs. Each
 * row says what is missing and opens the place that fixes it. `cc remote setup` grants most of it over adb and hands
 * over the server's address on first run, so on a client set up that way every row is already green.
 */
public final class MainActivity extends Activity {
    private static final int PERMISSIONS_REQUEST = 1;
    private static final long REFRESH_MILLISECONDS = 1000;
    // First-run hand-off from `cc remote setup`: the server's Tailscale name, its port, and whether to pair now.
    static final String EXTRA_SERVER = "server";
    static final String EXTRA_PORT = "port";
    static final String EXTRA_PAIR = "pair";

    private static final int GOOD = 0xFF43A047;
    private static final int MISSING = 0xFFE53935;
    private static final int OPTIONAL = 0xFFF9A825;

    /** One line of the checklist: a mark, a title, what to do, and a tap that does it. */
    private final class Row {
        final LinearLayout view;
        final TextView mark;
        final TextView detail;
        Runnable fix;
        private String shown;

        Row(String name) {
            view = new LinearLayout(MainActivity.this);
            view.setOrientation(LinearLayout.HORIZONTAL);
            view.setGravity(Gravity.CENTER_VERTICAL);
            view.setPadding(0, dp(10), 0, dp(10));
            mark = new TextView(MainActivity.this);
            mark.setGravity(Gravity.CENTER);
            mark.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
            mark.setTypeface(Typeface.DEFAULT_BOLD);
            mark.setTextColor(0xFFFFFFFF);
            view.addView(mark, new LinearLayout.LayoutParams(dp(30), dp(30)));
            LinearLayout words = new LinearLayout(MainActivity.this);
            words.setOrientation(LinearLayout.VERTICAL);
            words.setPadding(dp(14), 0, 0, 0);
            TextView title = new TextView(MainActivity.this);
            title.setText(name);
            title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
            words.addView(title);
            detail = new TextView(MainActivity.this);
            detail.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
            detail.setAlpha(0.75f);
            words.addView(detail);
            view.addView(words, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
            view.setOnClickListener(clicked -> {
                if (fix != null) {
                    fix.run();
                }
            });
        }

        void show(int color, String symbol, String text, Runnable action) {
            // Refreshed every second: touch the views only when something changed, so the screen settles.
            String state = color + symbol + text + (action != null);
            fix = action;
            if (state.equals(shown)) {
                return;
            }
            shown = state;
            GradientDrawable disc = new GradientDrawable();
            disc.setShape(GradientDrawable.OVAL);
            disc.setColor(color);
            mark.setBackground(disc);
            mark.setText(symbol);
            detail.setText(text);
            view.setClickable(action != null);
            view.setBackground(action != null ? ripple() : null);
        }

        void good(String text) {
            show(GOOD, "✓", text, null);
        }

        void missing(String text, Runnable action) {
            show(MISSING, "!", text, action);
        }

        void optional(String text, Runnable action) {
            show(OPTIONAL, "–", text, action);
        }
    }

    private EditText host;
    private EditText port;
    // The address fields, shown only while unpaired: setup fills them in, and a pairing belongs to one server.
    private LinearLayout addressBox;
    private Row server;
    private Row microphone;
    private Row notifications;
    private Row floating;
    private Row overTermux;
    private Row connection;
    private Button primary;
    private TextView status;
    private ForegroundWatcher usageCheck;
    private boolean pairing;
    private final Runnable refresher = new Runnable() {
        @Override
        public void run() {
            refresh();
            host.postDelayed(this, REFRESH_MILLISECONDS);
        }
    };

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        usageCheck = new ForegroundWatcher(this, inFront -> { });
        SharedPreferences preferences = getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE);

        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        int padding = dp(20);

        addressBox = new LinearLayout(this);
        addressBox.setOrientation(LinearLayout.VERTICAL);
        column.addView(addressBox);
        addressBox.addView(heading("Server"));
        host = new EditText(this);
        host.setSingleLine(true);
        host.setHint("the server's Tailscale name");
        host.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        host.setText(preferences.getString("host", VoxService.DEFAULT_HOST));
        addressBox.addView(host);
        port = new EditText(this);
        port.setSingleLine(true);
        port.setInputType(InputType.TYPE_CLASS_NUMBER);
        port.setText(String.valueOf(preferences.getInt("port", VoxService.DEFAULT_PORT)));
        addressBox.addView(port);

        column.addView(heading("Checklist"));
        server = row(column, "Paired with the server");
        microphone = row(column, "Microphone");
        notifications = row(column, "Notification");
        floating = row(column, "Floating button");
        overTermux = row(column, "Only over Termux");
        connection = row(column, "Connected");

        primary = new Button(this);
        primary.setOnClickListener(view -> {
            if (VoxService.armedNow) {
                startService(VoxService.intent(this, VoxService.ACTION_QUIT));
            } else {
                start();
            }
            host.postDelayed(this::refresh, 300);
        });
        LinearLayout.LayoutParams primaryLayout = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        primaryLayout.topMargin = dp(16);
        column.addView(primary, primaryLayout);

        status = caption("");
        column.addView(status);

        column.addView(heading("Using it"));
        column.addView(caption("ssh cc in Termux starts everything. Open a session: the floating microphone appears over "
                + "Termux. Tap it, speak, tap again; the text lands in that session's prompt, unsent. Long press "
                + "cancels. Drag the button where you like it; it stays there."));
        Button forget = new Button(this);
        forget.setText("Forget pairing");
        forget.setOnClickListener(view -> forget());
        column.addView(forget);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(column);
        // Target SDK 35 draws edge to edge: keep the content clear of the status and navigation bars.
        scroll.setOnApplyWindowInsetsListener((view, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
            column.setPadding(padding, padding + bars.top, padding, padding + bars.bottom);
            return insets;
        });
        setContentView(scroll);
        // Only a fresh launch hands over: a screen rebuilt (rotation, process restore, recents) would pair again.
        if (saved == null && (getIntent().getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0) {
            handOff(getIntent());
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handOff(intent);
    }

    /**
     * `cc remote setup` (over adb) hands over the server's address and asks to pair. Only an unpaired client takes
     * it, and only a Tailscale address: any app can send an intent, so a paired client never lets one repoint it.
     */
    private void handOff(Intent intent) {
        if (intent == null || !intent.hasExtra(EXTRA_SERVER)) {
            return;
        }
        SharedPreferences preferences = getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE);
        if (preferences.getString(VoxService.PREFERENCE_SECRET, null) != null) {
            status.setText("Already paired; the address was not changed. Forget pairing first to pair again.");
            return;
        }
        String offered = intent.getStringExtra(EXTRA_SERVER);
        int offeredPort = intent.getIntExtra(EXTRA_PORT, VoxService.DEFAULT_PORT);
        if (offered == null || !Tailnet.looksLikeTailscale(offered) || offeredPort < 1 || offeredPort > 65535) {
            status.setText("Ignored a server address that is not a Tailscale one.");
            return;
        }
        host.setText(offered.trim());
        port.setText(String.valueOf(offeredPort));
        saveAddress();
        if (intent.getBooleanExtra(EXTRA_PAIR, false)) {
            pair();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        VoxService.mainScreenOpen = true;
        if (VoxService.current != null) {
            VoxService.current.setAppInFront(true);
        }
        refresh();
        host.postDelayed(refresher, REFRESH_MILLISECONDS);
    }

    @Override
    protected void onPause() {
        host.removeCallbacks(refresher);
        VoxService.mainScreenOpen = false;
        if (VoxService.current != null) {
            VoxService.current.setAppInFront(false);
        }
        super.onPause();
    }

    private void refresh() {
        SharedPreferences preferences = getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE);
        boolean paired = preferences.getString(VoxService.PREFERENCE_SECRET, null) != null;
        String serverName = preferences.getString(VoxService.PREFERENCE_SERVER, "the server");
        int addressVisibility = paired ? android.view.View.GONE : android.view.View.VISIBLE;
        if (addressBox.getVisibility() != addressVisibility) {
            addressBox.setVisibility(addressVisibility);
        }
        if (paired) {
            String address = preferences.getString("host", "") + ":" + preferences.getInt("port", 0);
            server.good(address.startsWith(serverName + ".") ? address : serverName + " at " + address);
        } else if (pairing) {
            server.optional("Pairing…", null);
        } else {
            server.missing("Not paired. Run voxize-remote pair on the server, then tap here.", this::pair);
        }

        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            microphone.good("Allowed");
        } else {
            microphone.missing("Needed to record. Tap to allow.", this::requestPermissions);
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            notifications.good("Shows Record, Stop and Quit while armed");
        } else {
            notifications.optional("Without it the Record and Stop notification stays hidden. Tap to allow.",
                    this::requestPermissions);
        }
        if (Settings.canDrawOverlays(this)) {
            floating.good("Allowed to show over Termux");
        } else {
            floating.missing("Needed for the floating microphone. Tap, then allow Voxize Remote.", () ->
                    startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:" + getPackageName()))));
        }
        if (usageCheck.permitted()) {
            overTermux.good("The button shows while Termux is in front, and while it records");
        } else {
            overTermux.optional("Without Usage access the button shows over every app. Tap, then allow Voxize Remote.",
                    () -> startActivity(new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS,
                            Uri.parse("package:" + getPackageName()))));
        }
        if (VoxService.connectedNow) {
            connection.good("Ready. Go back to Termux and open a session.");
        } else if (VoxService.armedNow) {
            String problem = VoxService.problemNow;
            connection.missing(problem.isEmpty() ? "Connecting…" : problem, null);
        } else {
            connection.optional("Not started. ssh cc in Termux starts it, or tap Start.", this::start);
        }
        String primaryText = VoxService.armedNow ? "Stop" : "Start";
        if (!primaryText.contentEquals(primary.getText())) {
            primary.setText(primaryText);
        }
    }

    private Row row(LinearLayout column, String name) {
        Row row = new Row(name);
        column.addView(row.view);
        return row;
    }

    /** The address fields, checked and saved. */
    private void saveAddress() {
        SharedPreferences.Editor editor = getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE).edit();
        editor.putString("host", host.getText().toString().trim());
        int number;
        try {
            number = Integer.parseInt(port.getText().toString().trim());
        } catch (NumberFormatException invalid) {
            number = VoxService.DEFAULT_PORT;
        }
        if (number < 1 || number > 65535) {
            number = VoxService.DEFAULT_PORT;
        }
        port.setText(String.valueOf(number));
        editor.putInt("port", number);
        editor.commit();
    }

    private void pair() {
        if (pairing) {
            return;
        }
        saveAddress();
        SharedPreferences preferences = getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE);
        final String hostText = preferences.getString("host", VoxService.DEFAULT_HOST);
        final int portNumber = preferences.getInt("port", VoxService.DEFAULT_PORT);
        if (hostText.isEmpty()) {
            status.setText("Type the server's Tailscale name first.");
            return;
        }
        pairing = true;
        status.setText("Asking " + hostText + " to pair (voxize-remote pair must be waiting there).");
        refresh();
        new Thread(() -> {
            PairingClient client = null;
            try {
                client = new PairingClient(getApplicationContext(), hostText, portNumber);
                PairingClient.Offer offer = client.request(Build.MANUFACTURER + " " + Build.MODEL);
                final PairingClient session = client;
                runOnUiThread(() -> showCode(session, offer));
            } catch (Exception failure) {
                if (client != null) {
                    client.close();
                }
                runOnUiThread(() -> {
                    pairing = false;
                    status.setText("Not paired: " + failure.getMessage());
                    refresh();
                });
            }
        }, "voxize-pairing").start();
    }

    /** The code to type on the server; the dialog closes by itself once the server has checked it. */
    private void showCode(PairingClient client, PairingClient.Offer offer) {
        TextView code = new TextView(this);
        code.setText(offer.code);
        code.setTextSize(TypedValue.COMPLEX_UNIT_SP, 40);
        code.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        code.setGravity(Gravity.CENTER);
        code.setPadding(0, dp(16), 0, dp(8));
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Pair with " + offer.server)
                .setMessage("Type this code on the server, where voxize-remote pair asks for it.")
                .setView(code)
                .setCancelable(false)
                .setNegativeButton("Cancel", (shown, which) -> {
                    new Thread(() -> {
                        client.reject();
                        client.close();
                    }, "voxize-pairing").start();
                    pairing = false;
                    status.setText("Not paired.");
                    refresh();
                })
                .show();
        status.setText("Waiting for the code to be typed on the server.");
        new Thread(() -> awaitPairing(client, offer, dialog), "voxize-pairing").start();
    }

    private void awaitPairing(PairingClient client, PairingClient.Offer offer, AlertDialog dialog) {
        try {
            client.awaitResult();
            getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE).edit()
                    .putString(VoxService.PREFERENCE_DEVICE_ID, offer.deviceId)
                    .putString(VoxService.PREFERENCE_SECRET, Pairing.hex(offer.secret))
                    .putString(VoxService.PREFERENCE_SERVER, offer.server)
                    .commit();
            runOnUiThread(() -> {
                dialog.dismiss();
                pairing = false;
                status.setText("Paired with " + offer.server + ".");
                start();
            });
        } catch (Exception failure) {
            runOnUiThread(() -> {
                pairing = false;
                if (dialog.isShowing()) {
                    dialog.dismiss();
                    status.setText("Not paired: " + failure.getMessage());
                }
                refresh();
            });
        } finally {
            client.close();
        }
    }

    private void forget() {
        getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE).edit()
                .remove(VoxService.PREFERENCE_DEVICE_ID)
                .remove(VoxService.PREFERENCE_SECRET)
                .remove(VoxService.PREFERENCE_SERVER)
                .commit();
        startService(VoxService.intent(this, VoxService.ACTION_QUIT));
        status.setText("Pairing forgotten. On the server, voxize-remote unpair removes this client there too.");
        refresh();
    }

    private void requestPermissions() {
        List<String> missing = new ArrayList<>();
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.RECORD_AUDIO);
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.POST_NOTIFICATIONS);
        }
        if (!missing.isEmpty()) {
            requestPermissions(missing.toArray(new String[0]), PERMISSIONS_REQUEST);
        }
    }

    private void start() {
        saveAddress();
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions();
            return;
        }
        // Starting it again is harmless: the service reconnects only when the address or the pairing changed.
        try {
            startForegroundService(VoxService.intent(this, VoxService.ACTION_ARM));
        } catch (IllegalStateException notInFront) {
            // ForegroundServiceStartNotAllowedException: this screen was left before pairing finished.
            status.setText(status.getText() + " Run ssh cc in Termux to start it.");
            return;
        }
        host.postDelayed(this::refresh, 300);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        refresh();
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                && getSharedPreferences(VoxService.PREFERENCES, MODE_PRIVATE)
                        .getString(VoxService.PREFERENCE_SECRET, null) != null) {
            start();
        }
    }

    private TextView heading(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setAllCaps(true);
        view.setAlpha(0.7f);
        view.setPadding(0, dp(20), 0, dp(6));
        return view;
    }

    private TextView caption(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        view.setPadding(0, dp(10), 0, dp(4));
        return view;
    }

    private Drawable ripple() {
        TypedValue value = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackground, value, true);
        return getDrawable(value.resourceId);
    }

    private int dp(int value) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value,
                getResources().getDisplayMetrics()));
    }
}
