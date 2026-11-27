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
        if (intent != null && Intent.ACTION_SEND.equals(intent.getAction())) {
            String text = intent.getStringExtra(Intent.EXTRA_TEXT), subject = intent.getStringExtra(Intent.EXTRA_SUBJECT);
            if (text == null) return false;
            WidgetBridgePlugin.pendingShares.add(subject != null && !text.contains(subject) ? subject + '\n' + text : text);
            WidgetBridgePlugin.pendingAction = "places";
            intent.setAction(Intent.ACTION_MAIN);          // handled once, not again when the activity is recreated
            return true;
        }
        Uri data = intent == null ? null : intent.getData();
        if (data == null || !"baytna".equals(data.getScheme())) return false;
        WidgetBridgePlugin.pendingAction = data.getHost();
        return true;
    }
}
