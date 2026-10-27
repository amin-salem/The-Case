"""Generator + JVM contract checks, not an emulator/screenshot claim. No Gradle/APK build."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("game_android_patch", TOOLS / "patch_android.py")
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)


class CapturePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.old_app, self.old_manifest = patch.APP, patch.MANIFEST
        self.addCleanup(self.restore)
        patch.APP = self.root
        self.main = self.root / 'android/app/src/main'
        self.activity = self.main / 'kotlin/ir/gammly/the_case/MainActivity.kt'
        self.activity.parent.mkdir(parents=True)
        self.activity.write_text('package ir.gammly.the_case\nimport io.flutter.embedding.android.FlutterActivity\n'
                                 'class MainActivity: FlutterActivity() { fun keepBillingHooks() = "unchanged" }\n')
        patch.MANIFEST = self.main / 'AndroidManifest.xml'
        patch.MANIFEST.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:name="${applicationName}" android:label="the_case">'
            '<activity android:name=".MainActivity" android:exported="true" /></application></manifest>')
        self.java = self.main / 'java/ir/gammly/the_case'

    def restore(self):
        patch.APP, patch.MANIFEST = self.old_app, self.old_manifest

    def test_generation_is_idempotent_and_preserves_existing_flow(self):
        patch.patch_manifest()
        patch.patch_screen_capture()
        first = {str(p.relative_to(self.main)): p.read_text() for p in self.main.rglob('*') if p.is_file()}
        patch.patch_manifest()
        patch.patch_screen_capture()
        self.assertEqual(first, {str(p.relative_to(self.main)): p.read_text() for p in self.main.rglob('*') if p.is_file()})
        self.assertIn('SecureFlutterActivity()', self.activity.read_text())
        self.assertIn('keepBillingHooks() = "unchanged"', self.activity.read_text())
        self.assertIn('android:name="ir.gammly.the_case.SecureGameApplication"', patch.MANIFEST.read_text())
        self.assertIn('com.farsitel.bazaar', patch.MANIFEST.read_text())
        self.assertIn('android.permission.INTERNET', patch.MANIFEST.read_text())
        self.assertIn('android.intent.action.MY_PACKAGE_REPLACED', patch.MANIFEST.read_text())
        self.assertIn('android.intent.action.BOOT_COMPLETED', patch.MANIFEST.read_text())
        self.assertEqual({p.name for p in self.java.glob('*.java')},
            {'SecureGameWindows.java', 'SecureGameApplication.java', 'SecureFlutterActivity.java', 'EdgeInsetsFix.java', 'SystemSettingsBridge.java'})
        self.assertIn('patch_screen_capture()', (TOOLS / 'patch_android.py').read_text())
        for p in self.java.glob('*.java'):
            self.assertNotIn('BuildConfig.DEBUG', p.read_text())
            self.assertNotIn('clearFlags', p.read_text())

    def test_custom_application_or_unsupported_host_fails_explicitly(self):
        original = patch.MANIFEST.read_text()
        patch.MANIFEST.write_text(original.replace('${applicationName}', 'com.example.CustomApp'))
        with self.assertRaisesRegex(RuntimeError, 'Custom Application'):
            patch.patch_screen_capture()
        self.assertNotIn('SecureFlutterActivity', self.activity.read_text())
        patch.MANIFEST.write_text(original)
        self.activity.write_text(self.activity.read_text().replace('FlutterActivity()', 'CustomActivity()'))
        with self.assertRaisesRegex(RuntimeError, 'Unsupported MainActivity'):
            patch.patch_screen_capture()
        self.assertIn('${applicationName}', patch.MANIFEST.read_text())

    def test_java_generated_host_is_supported(self):
        self.activity.unlink()  # disposable test fixture only, never repository content
        target = self.main / 'java/ir/gammly/the_case/MainActivity.java'
        target.parent.mkdir(parents=True)
        target.write_text('package ir.gammly.the_case;\n'
                          'public class MainActivity extends io.flutter.embedding.android.FlutterActivity {}')
        patch.patch_screen_capture()
        self.assertIn('extends SecureFlutterActivity', target.read_text())

    def test_complete_regeneration_pipeline_applies_protection(self):
        gradle = self.root / 'android/app/build.gradle.kts'
        gradle.write_text('''android {
    namespace = "ir.gammly.the_case"
    defaultConfig { applicationId = "ir.gammly.the_case" }
    compileOptions { }
    buildTypes { release { signingConfig = signingConfigs.getByName("debug") } }
}
dependencies { }
''')
        original_activity = self.activity.read_text()
        original_manifest = patch.MANIFEST.read_text()
        for _ in range(2):
            # flutter create can restore the stock host/manifest on the next release generation.
            self.activity.write_text(original_activity)
            patch.MANIFEST.write_text(original_manifest)
            patch.main()
            self.assertIn('SecureFlutterActivity()', self.activity.read_text())
            self.assertIn('SecureGameApplication', patch.MANIFEST.read_text())
            self.assertIn('ir.gammly.parvandeh', gradle.read_text())
            self.assertIn('marketApplicationId', gradle.read_text())

    def test_flag_and_lifecycle_contract_on_jvm(self):
        self.assertTrue(shutil.which('javac') and shutil.which('java'), 'CI must provision a JDK; do not silently skip')
        patch.patch_screen_capture()
        stubs = {
            'android/os/Bundle.java': 'package android.os; public class Bundle {}',
            'android/os/Build.java': 'package android.os; public class Build { public static class VERSION { public static int SDK_INT = 26; } }',
            'android/view/WindowManager.java': 'package android.view; public interface WindowManager { class LayoutParams { public static final int FLAG_SECURE = 8192; } }',
            'android/view/View.java': '''package android.view;
public class View {
  public interface OnApplyWindowInsetsListener { WindowInsets onApplyWindowInsets(View v, WindowInsets insets); }
  public int bottomPadding = -1; public int background = 0; public OnApplyWindowInsetsListener listener;
  public View findViewById(int id) { return this; }
  public void setBackgroundColor(int c) { background = c; }
  public void setPadding(int l, int t, int r, int b) { bottomPadding = b; }
  public void setOnApplyWindowInsetsListener(OnApplyWindowInsetsListener l) { listener = l; }
  public void requestApplyInsets() { if (listener != null) listener.onApplyWindowInsets(this, new WindowInsets(48)); }
}''',
            'android/graphics/Insets.java': 'package android.graphics; public class Insets { public static final Insets NONE = new Insets(0); public final int bottom; public Insets(int b) { bottom = b; } }',
            'android/view/WindowInsets.java': '''package android.view;
import android.graphics.Insets;
public class WindowInsets {
  public final int nav; public WindowInsets(int nav) { this.nav = nav; }
  public static final class Type { public static int navigationBars() { return 2; } }
  public Insets getInsets(int types) { return new Insets(nav); }
  public static final class Builder {
    int nav; public Builder(WindowInsets i) { nav = i.nav; }
    public Builder setInsets(int types, Insets v) { nav = v.bottom; return this; }
    public WindowInsets build() { return new WindowInsets(nav); }
  }
}''',
            'android/content/ContentResolver.java': 'package android.content; public class ContentResolver {}',
            'android/net/Uri.java': 'package android.net; public class Uri { public final String s; Uri(String s) { this.s = s; } public static Uri parse(String s) { return new Uri(s); } }',
            'android/content/Intent.java': '''package android.content;
public class Intent {
  public static final int FLAG_ACTIVITY_NEW_TASK = 268435456;
  public final String action; public String extraKey, extraValue; public android.net.Uri data;
  public Intent(String action) { this.action = action; }
  public Intent putExtra(String k, String v) { extraKey = k; extraValue = v; return this; }
  public Intent setData(android.net.Uri u) { data = u; return this; }
  public Intent addFlags(int f) { return this; }
}''',
            'android/provider/Settings.java': '''package android.provider; import android.content.ContentResolver;
public class Settings {
  public static final String ACTION_APP_NOTIFICATION_SETTINGS = "notif", ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS = "battery",
      ACTION_APPLICATION_DETAILS_SETTINGS = "details", EXTRA_APP_PACKAGE = "pkg";
  public static class Secure { public static int getInt(ContentResolver r, String name, int d) { return 0; } }
}''',
            'io/flutter/embedding/engine/FlutterEngine.java': 'package io.flutter.embedding.engine; public class FlutterEngine { public io.flutter.plugin.common.BinaryMessenger getDartExecutor() { return new io.flutter.plugin.common.BinaryMessenger(); } }',
            'io/flutter/plugin/common/BinaryMessenger.java': 'package io.flutter.plugin.common; public class BinaryMessenger { public BinaryMessenger getBinaryMessenger() { return this; } }',
            'io/flutter/plugin/common/MethodCall.java': 'package io.flutter.plugin.common; public class MethodCall { public final String method; public final Object arguments; public MethodCall(String m, Object a) { method = m; arguments = a; } }',
            'io/flutter/plugin/common/MethodChannel.java': '''package io.flutter.plugin.common;
public class MethodChannel {
  public interface Result { void success(Object o); void notImplemented(); }
  public interface MethodCallHandler { void onMethodCall(MethodCall c, Result r); }
  public static MethodCallHandler last; public static String name;
  public MethodChannel(BinaryMessenger m, String n) { name = n; }
  public void setMethodCallHandler(MethodCallHandler h) { last = h; }
}''',
            'android/view/Window.java': 'package android.view; public class Window { public int flags = 1; private final View decor = new View(); public View getDecorView() { return decor; } public void addFlags(int value) { flags |= value; } public void clearSecure() { flags &= ~8192; } }',
            'android/app/Activity.java': '''package android.app;
import android.os.Bundle; import android.view.Window;
public class Activity {
  private final Window window = new Window(); public boolean recents = true;
  public Window getWindow() { return window; }
  public android.content.ContentResolver getContentResolver() { return new android.content.ContentResolver(); }
  public void setRecentsScreenshotEnabled(boolean value) { recents = value; }
  public String getPackageName() { return "ir.gammly.parvandeh"; }
  public static android.content.Intent started; public static boolean fail;
  public void startActivity(android.content.Intent i) { if (fail) throw new RuntimeException("no screen"); started = i; }

  public void onCreate(Bundle state) {} public void onResume() {} public void onWindowFocusChanged(boolean focus) {}
}''',
            'android/app/Application.java': '''package android.app;
import android.os.Bundle;
public class Application {
  public boolean created = false; public ActivityLifecycleCallbacks registered;
  public void onCreate() { created = true; }
  public void registerActivityLifecycleCallbacks(ActivityLifecycleCallbacks c) { if (!created) throw new AssertionError(); registered = c; }
  public interface ActivityLifecycleCallbacks {
    default void onActivityPreCreated(Activity a, Bundle b) {}
    void onActivityCreated(Activity a, Bundle b); void onActivityStarted(Activity a); void onActivityResumed(Activity a);
    void onActivityPaused(Activity a); void onActivityStopped(Activity a); void onActivitySaveInstanceState(Activity a, Bundle b);
    void onActivityDestroyed(Activity a);
  }
}''',
            'io/flutter/embedding/android/FlutterActivity.java': '''package io.flutter.embedding.android;
import android.app.Activity; import android.os.Bundle;
public class FlutterActivity extends Activity {
  @Override public void onCreate(Bundle state) { if ((getWindow().flags & 8192) == 0) throw new AssertionError("first frame unprotected"); }
  public void configureFlutterEngine(io.flutter.embedding.engine.FlutterEngine e) {}
  @Override public void onResume() { getWindow().clearSecure(); }
  @Override public void onWindowFocusChanged(boolean focus) { getWindow().clearSecure(); }
}''',
            'ir/gammly/the_case/CaptureContract.java': '''package ir.gammly.the_case;
import android.app.Activity; import android.os.Build;
public class CaptureContract {
  static void protectedWindow(Activity a) {
    if ((a.getWindow().flags & 8192) == 0 || (a.getWindow().flags & 1) == 0) throw new AssertionError("secure flag missing or other flags changed");
    if (Build.VERSION.SDK_INT >= 33 && a.recents) throw new AssertionError("recents enabled");
  }
  public static void main(String[] args) {
    for (int sdk : new int[]{26, 29, 33, 35}) {
      Build.VERSION.SDK_INT = sdk;
      SecureFlutterActivity host = new SecureFlutterActivity();
      host.onCreate(null); protectedWindow(host);
      if (sdk >= 30) {  // the three-button bar height (48) is kept as padding and not passed on to Flutter
        android.view.View content = host.getWindow().getDecorView();
        if (content.bottomPadding != 48) throw new AssertionError("bar height not kept: " + content.bottomPadding);
        if (content.background != 0xFF17181A) throw new AssertionError("background not set");
      } else if (host.getWindow().getDecorView().bottomPadding != -1) throw new AssertionError("old Android was touched");
      // the settings shortcut: right screen per request, fallback to app details, and a failure never throws
      host.configureFlutterEngine(new io.flutter.embedding.engine.FlutterEngine());
      if (!io.flutter.plugin.common.MethodChannel.name.equals("ir.gammly.parvandeh/system")) throw new AssertionError("channel name");
      final Object[] answer = new Object[1];
      io.flutter.plugin.common.MethodChannel.Result res = new io.flutter.plugin.common.MethodChannel.Result() {
        public void success(Object o) { answer[0] = o; } public void notImplemented() { answer[0] = "ni"; } };
      io.flutter.plugin.common.MethodChannel.last.onMethodCall(new io.flutter.plugin.common.MethodCall("open", "notifications"), res);
      if (!Boolean.TRUE.equals(answer[0]) || !"notif".equals(Activity.started.action) || !"ir.gammly.parvandeh".equals(Activity.started.extraValue)) throw new AssertionError("notification screen");
      io.flutter.plugin.common.MethodChannel.last.onMethodCall(new io.flutter.plugin.common.MethodCall("open", "battery"), res);
      if (!"battery".equals(Activity.started.action)) throw new AssertionError("battery screen");
      io.flutter.plugin.common.MethodChannel.last.onMethodCall(new io.flutter.plugin.common.MethodCall("open", null), res);
      if (!"details".equals(Activity.started.action) || !"package:ir.gammly.parvandeh".equals(Activity.started.data.s)) throw new AssertionError("app details");
      io.flutter.plugin.common.MethodChannel.last.onMethodCall(new io.flutter.plugin.common.MethodCall("nope", null), res);
      if (!"ni".equals(answer[0])) throw new AssertionError("unknown method");
      Activity.fail = true;
      io.flutter.plugin.common.MethodChannel.last.onMethodCall(new io.flutter.plugin.common.MethodCall("open", "notifications"), res);
      if (!Boolean.FALSE.equals(answer[0])) throw new AssertionError("failure must answer false"); Activity.fail = false;
      host.getWindow().clearSecure(); host.onResume(); protectedWindow(host);
      host.onWindowFocusChanged(false); protectedWindow(host);
      host.onWindowFocusChanged(true); protectedWindow(host);
      SecureGameApplication app = new SecureGameApplication(); app.onCreate();
      if (app.registered != app) throw new AssertionError("callbacks missing");
      // A non-Flutter in-app billing bridge is covered without patching third-party code.
      Activity billing = new Activity();
      app.onActivityPreCreated(billing, null); protectedWindow(billing);
      billing.getWindow().clearSecure(); app.onActivityCreated(billing, null); protectedWindow(billing);
      billing.getWindow().clearSecure(); app.onActivityStarted(billing); protectedWindow(billing);
      billing.getWindow().clearSecure(); app.onActivityResumed(billing); protectedWindow(billing);
      billing.getWindow().clearSecure(); app.onActivityPaused(billing); protectedWindow(billing);
      billing.getWindow().clearSecure(); app.onActivityStopped(billing); protectedWindow(billing);
      billing.getWindow().clearSecure(); app.onActivitySaveInstanceState(billing, null); protectedWindow(billing);
    }
  }
}''',
        }
        source = self.root / 'contract'
        for path, code in stubs.items():
            p = source / path
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(code)
        classes = self.root / 'classes'
        result = subprocess.run(['javac', '-d', str(classes), *map(str, source.rglob('*.java')), *map(str, self.java.glob('*.java'))], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        ran = subprocess.run(['java', '-cp', str(classes), 'ir.gammly.the_case.CaptureContract'], capture_output=True, text=True)
        self.assertEqual(ran.returncode, 0, ran.stderr)


if __name__ == '__main__':
    unittest.main()
