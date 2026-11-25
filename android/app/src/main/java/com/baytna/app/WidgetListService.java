package com.baytna.app;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;
import org.json.JSONArray;
import org.json.JSONObject;

public class WidgetListService extends RemoteViewsService {
    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new Factory(getApplicationContext());
    }

    static class Factory implements RemoteViewsFactory {
        private final Context context;
        private JSONArray items = new JSONArray();

        Factory(Context context) { this.context = context; }

        @Override public void onCreate() {}
        @Override public void onDestroy() {}

        @Override
        public void onDataSetChanged() {
            try {
                items = new JSONArray(context.getSharedPreferences(WidgetBridgePlugin.PREFS, 0).getString("items", "[]"));
            } catch (Exception e) {
                items = new JSONArray();
            }
        }

        @Override public int getCount() { return items.length(); }

        @Override
        public RemoteViews getViewAt(int position) {
            RemoteViews row = new RemoteViews(context.getPackageName(), R.layout.widget_row);
            JSONObject it = items.optJSONObject(position);
            if (it == null) return row;
            row.setTextViewText(R.id.row_title, it.optString("t"));
            row.setTextViewText(R.id.row_meta, it.optString("g"));
            int color;
            try { color = Color.parseColor(it.optString("c", "#8E8E93")); } catch (Exception e) { color = Color.GRAY; }
            row.setTextColor(R.id.row_dot, color);
            row.setTextColor(R.id.row_meta, color);
            row.setOnClickFillInIntent(R.id.row_root, new Intent());
            return row;
        }

        @Override public RemoteViews getLoadingView() { return null; }
        @Override public int getViewTypeCount() { return 1; }
        @Override public long getItemId(int position) { return position; }
        @Override public boolean hasStableIds() { return false; }
    }
}
