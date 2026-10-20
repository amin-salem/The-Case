package __PACKAGE__;

import android.app.Activity;
import android.os.Build;
import android.view.WindowManager;

/** Generated into the game only. Always on; no release/debug or sharing bypass. */
public final class SecureGameWindows {
    private SecureGameWindows() {}

    public static void apply(Activity activity) {
        activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        if (Build.VERSION.SDK_INT >= 33) {
            activity.setRecentsScreenshotEnabled(false);
        }
    }
}
