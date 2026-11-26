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
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.text.style.RelativeSizeSpan;
import android.text.style.StyleSpan;
import android.view.View;
import android.widget.RemoteViews;
import org.json.JSONArray;
import org.json.JSONObject;

/** Resizable home-screen widget: a count and a plus button when small; with room, the bills paid this month, the categories with their counts, and the latest items. */
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

    /** The category colours are picked for the app's tiles; on the widget's dark glass they read better a little lighter. */
    static int lighten(int c) {
        return Color.rgb((Color.red(c) + 255) / 2, (Color.green(c) + 255) / 2, (Color.blue(c) + 255) / 2);
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
            int paid = prefs.getInt("billsPaid", 0), total = prefs.getInt("billsTotal", 0);
            v.setViewVisibility(R.id.widget_bills, signedIn && total > 0 ? View.VISIBLE : View.GONE);
            v.setTextViewText(R.id.widget_bills, context.getString(R.string.widget_bills, paid, total));

            // Up to four categories, each a tile with its count in the category's colour. They need the taller sizes.
            JSONArray cats;
            try { cats = new JSONArray(prefs.getString("cats", "[]")); } catch (Exception e) { cats = new JSONArray(); }
            boolean showCats = signedIn && cats.length() > 0 && h >= 170;
            v.setViewVisibility(R.id.widget_cats, showCats ? View.VISIBLE : View.GONE);
            int[] tiles = {R.id.widget_cat1, R.id.widget_cat2, R.id.widget_cat3, R.id.widget_cat4};
            for (int i = 0; i < tiles.length; i++) {
                JSONObject c = showCats ? cats.optJSONObject(i) : null;
                v.setViewVisibility(tiles[i], c == null ? View.GONE : View.VISIBLE);
                if (c == null) continue;
                String n = String.valueOf(c.optInt("x", 0));
                SpannableString text = new SpannableString(n + "\n" + c.optString("n"));
                int color;
                try { color = Color.parseColor(c.optString("c", "#8E8E93")); } catch (Exception e) { color = Color.GRAY; }
                text.setSpan(new ForegroundColorSpan(lighten(color)), 0, n.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                text.setSpan(new StyleSpan(Typeface.BOLD), 0, n.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                text.setSpan(new RelativeSizeSpan(1.6f), 0, n.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                v.setTextViewText(tiles[i], text);
            }
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
