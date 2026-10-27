package __PACKAGE__;

import android.app.Activity;
import android.graphics.Insets;
import android.os.Build;
import android.provider.Settings;
import android.view.View;
import android.view.WindowInsets;

/**
 * Android 15 draws every app edge to edge. On a phone with the classic three-button navigation bar (many Samsung
 * models) Flutter can then end up drawing the bottom of the app UNDER that bar. Here, and only with the three-button
 * bar (Settings.Secure navigation_mode == 0), the bar's height is kept as padding under the app and removed from
 * what Flutter is told, so nothing is counted twice. Phones with gesture navigation, and Android 10 and older, are
 * not touched: they look exactly as before.
 */
final class EdgeInsetsFix {
    private EdgeInsetsFix() {}

    static void install(final Activity activity) {
        try {
            if (Build.VERSION.SDK_INT < 30) return;
            if (Settings.Secure.getInt(activity.getContentResolver(), "navigation_mode", 0) != 0) return;
            View decor = activity.getWindow().getDecorView();
            View content = decor.findViewById(16908290); // android.R.id.content
            if (content == null) return;
            decor.setBackgroundColor(0xFF17181A); // the app's night colour shows behind the bar, never white
            content.setOnApplyWindowInsetsListener((v, insets) -> {
                int bottom = insets.getInsets(WindowInsets.Type.navigationBars()).bottom;
                v.setPadding(0, 0, 0, bottom);
                return new WindowInsets.Builder(insets).setInsets(WindowInsets.Type.navigationBars(), Insets.NONE).build();
            });
            content.requestApplyInsets();
        } catch (Throwable ignored) {
            // never let a layout nicety stop the game from starting
        }
    }
}
