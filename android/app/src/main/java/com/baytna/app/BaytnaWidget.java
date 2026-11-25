package com.baytna.app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.widget.RemoteViews;

/** Resizable home-screen widget: a count and a plus button when small, the latest items when there is room. */
public class BaytnaWidget extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager mgr, int[] ids) {
        for (int id : ids) update(context, mgr, id);
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager mgr, int id, Bundle options) {
        update(context, mgr, id);
    }

    static void refreshAll(Context context) {
        AppWidgetManager mgr = AppWidgetManager.getInstance(context);
        int[] ids = mgr.getAppWidgetIds(new ComponentName(context, BaytnaWidget.class));
        for (int id : ids) update(context, mgr, id);
        mgr.notifyAppWidgetViewDataChanged(ids, R.id.widget_list);
    }

    private static PendingIntent open(Context context, String uri, int requestCode, boolean mutable) {
        Intent intent = new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        if (uri != null) intent.setAction(Intent.ACTION_VIEW).setData(Uri.parse(uri));
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (mutable && Build.VERSION.SDK_INT >= 31) flags |= PendingIntent.FLAG_MUTABLE; else flags |= PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getActivity(context, requestCode, intent, flags);
    }

    static void update(Context context, AppWidgetManager mgr, int id) {
        SharedPreferences prefs = context.getSharedPreferences(WidgetBridgePlugin.PREFS, 0);
        boolean signedIn = prefs.getBoolean("signedIn", false);
        int count = prefs.getInt("count", 0);
        Bundle o = mgr.getAppWidgetOptions(id);
        int w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250);
        int h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 110);
        boolean compact = h < 100 || w < 170;

        RemoteViews v = new RemoteViews(context.getPackageName(), compact ? R.layout.widget_small : R.layout.widget_list);
        v.setTextViewText(R.id.widget_count, signedIn ? String.valueOf(count) : "–");
        v.setTextViewText(R.id.widget_label, !signedIn ? context.getString(R.string.widget_signin)
            : count == 0 ? context.getString(R.string.widget_none) : context.getString(R.string.widget_pending));
        v.setOnClickPendingIntent(R.id.widget_root, open(context, null, 1, false));
        v.setOnClickPendingIntent(R.id.widget_add, open(context, "baytna://add", 2, false));
        if (!compact) {
            Intent svc = new Intent(context, WidgetListService.class).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id);
            svc.setData(Uri.parse(svc.toUri(Intent.URI_INTENT_SCHEME)));
            v.setRemoteAdapter(R.id.widget_list, svc);
            v.setEmptyView(R.id.widget_list, R.id.widget_empty);
            v.setTextViewText(R.id.widget_empty, context.getString(signedIn ? R.string.widget_empty : R.string.widget_signin_long));
            v.setPendingIntentTemplate(R.id.widget_list, open(context, null, 3, true));
        }
        mgr.updateAppWidget(id, v);
    }
}
