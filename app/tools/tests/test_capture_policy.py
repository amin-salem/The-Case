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
        self.assertEqual({p.name for p in self.java.glob('*.java')},
            {'SecureGameWindows.java', 'SecureGameApplication.java', 'SecureFlutterActivity.java'})
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
            'android/view/Window.java': 'package android.view; public class Window { public int flags = 1; public void addFlags(int value) { flags |= value; } public void clearSecure() { flags &= ~8192; } }',
            'android/app/Activity.java': '''package android.app;
import android.os.Bundle; import android.view.Window;
public class Activity {
  private final Window window = new Window(); public boolean recents = true;
  public Window getWindow() { return window; }
  public void setRecentsScreenshotEnabled(boolean value) { recents = value; }
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
