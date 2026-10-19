package __PACKAGE__;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;

/** Covers every activity owned by this application, including the billing bridge. */
public final class SecureGameApplication extends Application implements Application.ActivityLifecycleCallbacks {
    @Override public void onCreate() {
        super.onCreate();
        registerActivityLifecycleCallbacks(this);
    }

    // API 29+ calls this before Activity.onCreate. On older versions onActivityCreated
    // still runs before the first draw; the Flutter host also protects before super.onCreate.
    @Override public void onActivityPreCreated(Activity activity, Bundle state) { SecureGameWindows.apply(activity); }
    @Override public void onActivityCreated(Activity activity, Bundle state) { SecureGameWindows.apply(activity); }
    @Override public void onActivityStarted(Activity activity) { SecureGameWindows.apply(activity); }
    @Override public void onActivityResumed(Activity activity) { SecureGameWindows.apply(activity); }
    @Override public void onActivityPaused(Activity activity) { SecureGameWindows.apply(activity); }
    @Override public void onActivityStopped(Activity activity) { SecureGameWindows.apply(activity); }
    @Override public void onActivitySaveInstanceState(Activity activity, Bundle state) { SecureGameWindows.apply(activity); }
    @Override public void onActivityDestroyed(Activity activity) {}
}
