package com.baytna.app;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(WidgetBridgePlugin.class);
        super.onCreate(savedInstanceState);
        capture(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (capture(intent) && bridge != null) bridge.triggerWindowJSEvent("baytnaAction");
    }

    // baytna://add comes from the plus button of the widget; the web app picks it up via WidgetBridge.consumeAction().
    private boolean capture(Intent intent) {
        Uri data = intent == null ? null : intent.getData();
        if (data == null || !"baytna".equals(data.getScheme())) return false;
        WidgetBridgePlugin.pendingAction = data.getHost();
        return true;
    }
}
