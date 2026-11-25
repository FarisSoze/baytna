package com.baytna.app;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/** Hands the current list to the home-screen widget and passes widget taps back to the web app. */
@CapacitorPlugin(name = "WidgetBridge")
public class WidgetBridgePlugin extends Plugin {
    static final String PREFS = "baytna_widget";
    static volatile String pendingAction = null;

    @PluginMethod
    public void setItems(PluginCall call) {
        getContext().getSharedPreferences(PREFS, 0).edit()
            .putString("items", call.getString("items", "[]"))
            .putInt("count", call.getInt("count", 0))
            .putBoolean("signedIn", call.getBoolean("signedIn", false))
            .apply();
        BaytnaWidget.refreshAll(getContext());
        call.resolve();
    }

    @PluginMethod
    public void consumeAction(PluginCall call) {
        JSObject res = new JSObject();
        res.put("action", pendingAction == null ? "" : pendingAction);
        pendingAction = null;
        call.resolve(res);
    }
}
