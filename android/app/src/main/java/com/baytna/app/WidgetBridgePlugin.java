package com.baytna.app;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.speech.RecognizerIntent;
import androidx.activity.result.ActivityResult;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/**
 * Hands the current list to the home-screen widget and passes widget taps back to the web app.
 * Also carries the "Sign in with ChatGPT" round trip: opens the browser, catches the loopback callback, keeps the tokens in app-private storage.
 */
@CapacitorPlugin(name = "WidgetBridge")
public class WidgetBridgePlugin extends Plugin {
    static final String PREFS = "baytna_widget";
    static final String SECURE = "baytna_secure";
    static final String CALLBACK = "/auth/callback?";
    static final String PAGE = "<!doctype html><html lang=\"ar\" dir=\"rtl\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        + "<title>بيتنا</title><body style=\"margin:0;min-height:100vh;display:grid;place-items:center;background:#0B0B0C;color:#F5F1E8;font-family:system-ui,sans-serif;text-align:center\">"
        + "<div><h1 style=\"font-weight:600\">تم الربط</h1><p style=\"opacity:.7\">ارجع إلى تطبيق بيتنا.</p>"
        + "<a href=\"baytna://gpt\" style=\"display:inline-block;margin-top:18px;padding:14px 28px;border-radius:16px;background:#D9BE8A;color:#1B1710;text-decoration:none;font-weight:600\">فتح بيتنا</a></div>"
        + "<script>location.href='baytna://gpt'</script></body></html>";

    static volatile String pendingAction = null;
    static final java.util.List<String> pendingShares = java.util.Collections.synchronizedList(new java.util.ArrayList<>());
    static volatile String authQuery = null;
    private static volatile ServerSocket authServer = null;

    @PluginMethod
    public void setItems(PluginCall call) {
        getContext().getSharedPreferences(PREFS, 0).edit()
            .putString("items", call.getString("items", "[]"))
            .putInt("count", call.getInt("count", 0))
            .putBoolean("signedIn", call.getBoolean("signedIn", false))
            .putString("cats", call.getString("cats", "[]"))
            .putInt("billsPaid", call.getInt("billsPaid", 0))
            .putInt("billsTotal", call.getInt("billsTotal", 0))
            .apply();
        BaytnaWidget.refreshAll(getContext());
        call.resolve();
    }

    /** Texts shared into the app (Google Maps links), handed to the web app once. */
    @PluginMethod
    public void consumeShare(PluginCall call) {
        com.getcapacitor.JSArray items = new com.getcapacitor.JSArray();
        synchronized (pendingShares) { for (String s : pendingShares) items.put(s); pendingShares.clear(); }
        JSObject res = new JSObject();
        res.put("items", items);
        call.resolve(res);
    }

    @PluginMethod
    public void consumeAction(PluginCall call) {
        JSObject res = new JSObject();
        res.put("action", pendingAction == null ? "" : pendingAction);
        pendingAction = null;
        call.resolve(res);
    }

    /** Switches the launcher icon between its night and day versions by enabling one of two activity aliases. */
    @PluginMethod
    public void setIcon(PluginCall call) {
        boolean day = "day".equals(call.getString("name", "night"));
        PackageManager pm = getContext().getPackageManager();
        String pkg = getContext().getPackageName();
        try {
            pm.setComponentEnabledSetting(new ComponentName(pkg, "com.baytna.app.IconDay"),
                day ? PackageManager.COMPONENT_ENABLED_STATE_ENABLED : PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
            pm.setComponentEnabledSetting(new ComponentName(pkg, "com.baytna.app.IconNight"),
                day ? PackageManager.COMPONENT_ENABLED_STATE_DISABLED : PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
            call.resolve();
        } catch (Exception e) {
            call.reject("icon", e);
        }
    }

    @PluginMethod
    public void secureGet(PluginCall call) {
        JSObject res = new JSObject();
        res.put("value", getContext().getSharedPreferences(SECURE, 0).getString(call.getString("key", ""), ""));
        call.resolve(res);
    }

    @PluginMethod
    public void secureSet(PluginCall call) {
        getContext().getSharedPreferences(SECURE, 0).edit().putString(call.getString("key", ""), call.getString("value", "")).apply();
        call.resolve();
    }

    @PluginMethod
    public void openUrl(PluginCall call) {
        String url = call.getString("url", "");
        if (!url.startsWith("https://")) { call.reject("https only"); return; }
        try {
            getContext().startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            call.resolve();
        } catch (Exception e) {
            call.reject("no browser", e);
        }
    }

    /** Shares a picture of the list through the system share sheet (WhatsApp, Messages, ...). */
    @PluginMethod
    public void shareImage(PluginCall call) {
        try {
            byte[] png = android.util.Base64.decode(call.getString("data", ""), android.util.Base64.DEFAULT);
            java.io.File dir = new java.io.File(getContext().getCacheDir(), "share");
            dir.mkdirs();
            java.io.File file = new java.io.File(dir, "baytna-list.png");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(file)) { out.write(png); }
            Uri uri = androidx.core.content.FileProvider.getUriForFile(getContext(), getContext().getPackageName() + ".fileprovider", file);
            Intent send = new Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            send.setClipData(android.content.ClipData.newRawUri("", uri));
            getActivity().startActivity(Intent.createChooser(send, "مشاركة القائمة"));
            call.resolve();
        } catch (Exception e) {
            call.reject("share failed", e);
        }
    }

    /** Voice input: the system speech dialog listens and hands back the text, so the app itself needs no microphone permission. */
    @PluginMethod
    public void listen(PluginCall call) {
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, call.getString("lang", "ar-SA"))
            .putExtra(RecognizerIntent.EXTRA_PROMPT, "وش تحتاجون؟");
        try {
            startActivityForResult(call, intent, "speechResult");
        } catch (Exception e) {
            call.reject("unavailable", e);
        }
    }

    @ActivityCallback
    private void speechResult(PluginCall call, ActivityResult result) {
        if (call == null) return;
        java.util.ArrayList<String> found = result.getResultCode() == Activity.RESULT_OK && result.getData() != null
            ? result.getData().getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS) : null;
        JSObject res = new JSObject();
        res.put("text", found == null || found.isEmpty() ? "" : found.get(0));
        call.resolve(res);
    }

    @PluginMethod
    public void stopListening(PluginCall call) {
        call.resolve();   // the system dialog closes itself
    }

    /** Listens on 127.0.0.1 only, for one sign-in callback, for at most ten minutes. */
    @PluginMethod
    public void authListen(PluginCall call) {
        stopAuth();
        authQuery = null;
        final ServerSocket server;
        try {
            server = new ServerSocket(call.getInt("port", 1455), 4, InetAddress.getByName("127.0.0.1"));
            server.setSoTimeout(600000);
        } catch (Exception e) {
            call.reject("port busy", e);
            return;
        }
        authServer = server;
        new Thread(() -> {
            try {
                while (!server.isClosed()) {
                    final Socket s = server.accept();                 // throws after ten idle minutes, which ends the thread
                    try (s) {
                        s.setSoTimeout(5000);
                        String line = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8)).readLine();
                        String[] parts = line == null ? new String[0] : line.split(" ");
                        String target = parts.length > 1 ? parts[1] : "";
                        boolean ok = target.startsWith(CALLBACK);
                        byte[] body = (ok ? PAGE : "Not found").getBytes(StandardCharsets.UTF_8);
                        OutputStream out = s.getOutputStream();
                        out.write(("HTTP/1.1 " + (ok ? "200 OK" : "404 Not Found") + "\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: " + body.length
                            + "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                        out.write(body);
                        out.flush();
                        if (ok) {
                            authQuery = target.substring(CALLBACK.length());
                            if (bridge != null) bridge.triggerWindowJSEvent("baytnaAuth");
                            break;
                        }
                    } catch (java.io.IOException e) {
                        // a browser pre-connection that never sent a request: keep waiting for the real one
                    }
                }
            } catch (Exception ignored) {
            } finally {
                try { server.close(); } catch (Exception ignored) { }
            }
        }, "baytna-auth").start();
        call.resolve();
    }

    @PluginMethod
    public void authResult(PluginCall call) {
        JSObject res = new JSObject();
        res.put("query", authQuery == null ? "" : authQuery);
        authQuery = null;
        call.resolve(res);
    }

    private static void stopAuth() {
        ServerSocket s = authServer;
        authServer = null;
        if (s != null) try { s.close(); } catch (Exception ignored) { }
    }
}
