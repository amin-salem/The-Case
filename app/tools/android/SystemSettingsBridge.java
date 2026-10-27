package __PACKAGE__;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Opens the phone's own settings screens for the app (notifications, battery) from Flutter, so the player can fix
 * a switched-off notification permission with one tap. It needs no manifest permission: these are plain settings
 * screens, not REQUEST_IGNORE_BATTERY_OPTIMIZATIONS. Channel: ir.gammly.parvandeh/system, method "open",
 * argument "notifications" | "battery" | "app". Always answers true/false and never throws into Flutter.
 * Method "installer" answers the installer package name (the store the app came from) or "".
 */
final class SystemSettingsBridge {
    static final String CHANNEL = "ir.gammly.parvandeh/system";

    private SystemSettingsBridge() {}

    static void install(final Activity activity, FlutterEngine engine) {
        try {
            new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL).setMethodCallHandler((call, result) -> {
                if ("installer".equals(call.method)) {
                    result.success(installer(activity));
                    return;
                }
                if (!"open".equals(call.method)) {
                    result.notImplemented();
                    return;
                }
                result.success(open(activity, call.arguments == null ? "app" : String.valueOf(call.arguments)));
            });
        } catch (Throwable ignored) {
            // the app works without the shortcut; Flutter then shows the written steps
        }
    }

    /** The package name of the store that installed the app («com.farsitel.bazaar»); "" when unknown. Never throws. */
    static String installer(Activity activity) {
        try {
            String pkg = activity.getPackageName();
            String name = android.os.Build.VERSION.SDK_INT >= 30
                    ? activity.getPackageManager().getInstallSourceInfo(pkg).getInstallingPackageName()
                    : activity.getPackageManager().getInstallerPackageName(pkg);
            return name == null ? "" : name;
        } catch (Throwable e) {
            return "";
        }
    }

    static boolean open(Activity activity, String what) {
        String pkg = activity.getPackageName();
        if ("notifications".equals(what) && start(activity, new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, pkg))) return true;
        if ("battery".equals(what) && start(activity, new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))) return true;
        return start(activity, new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(Uri.parse("package:" + pkg)));
    }

    private static boolean start(Activity activity, Intent intent) {
        try {
            activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        } catch (Throwable e) {
            return false;
        }
    }
}
