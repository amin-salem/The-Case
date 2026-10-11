#!/usr/bin/env python3
"""Prepares the android/ folder that `flutter create` made for admin_app (safe to run many times).

    python3 tools/patch_android.py

- applicationId: the ONE constant below. The app is only sideloaded, never published in a store.
- AndroidManifest.xml: INTERNET, no cleartext traffic, Persian app name, USE_BIOMETRIC.
- MainActivity.kt: FragmentActivity (local_auth needs it) + a channel that sets Android FLAG_SECURE.
- styles.xml: AppCompat parent theme (the biometric prompt needs it); minSdk 24.
- Release signing from android/key.properties (the same permanent key as the main app) when it exists.
- res/: the launcher icon (tools/make_icon.py).
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

# >>> change the Android application id here (one place) <<<
APPLICATION_ID = "app.parvandeh.admin"
APP_LABEL = "پنل پرونده"

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
MAIN = ANDROID / "app" / "src" / "main"
MANIFEST = MAIN / "AndroidManifest.xml"

ACTIVITY = """package {package}

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        // FLAG_SECURE: no screenshots, blank preview in the recent-apps list
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.parvandeh.admin/window")
            .setMethodCallHandler {{ call, result ->
                if (call.method == "setSecure") {{
                    if (call.arguments == true) {{
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    }} else {{
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }}
                    result.success(null)
                }} else {{
                    result.notImplemented()
                }}
            }}
    }}
}}
"""


def patch_manifest() -> None:
    s = MANIFEST.read_text(encoding="utf-8")
    for perm in ("android.permission.INTERNET", "android.permission.USE_BIOMETRIC"):
        if perm not in s:
            s = s.replace("<application", f'<uses-permission android:name="{perm}"/>\n    <application', 1)
            print(f"  manifest: + {perm}")
    s = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', s, count=1)
    if "usesCleartextTraffic" not in s:
        s = s.replace("<application", '<application android:usesCleartextTraffic="false"', 1)
    MANIFEST.write_text(s, encoding="utf-8")


def patch_activity() -> None:
    found = list(MAIN.glob("kotlin/**/MainActivity.kt")) + list(MAIN.glob("java/**/MainActivity.*"))
    if not found:
        sys.exit("MainActivity not found")
    path = found[0]
    m = re.search(r"^package\s+([\w.]+)", path.read_text(encoding="utf-8"), re.M)
    if not m:
        sys.exit("MainActivity has no package line")
    if path.suffix != ".kt":
        path.unlink()
        path = path.with_suffix(".kt")
    path.write_text(ACTIVITY.format(package=m.group(1)), encoding="utf-8")
    print(f"  {path.name}: FlutterFragmentActivity + FLAG_SECURE channel")


def patch_styles() -> None:
    for f in MAIN.glob("res/values*/styles.xml"):
        s = f.read_text(encoding="utf-8")
        n = re.sub(r'(<style name="(?:LaunchTheme|NormalTheme)" parent=")[^"]*(")',
                   r"\1Theme.AppCompat.Light.NoActionBar\2", s)
        if n != s:
            f.write_text(n, encoding="utf-8")
            print(f"  {f.parent.name}/styles.xml: AppCompat parent")


def patch_gradle() -> None:
    kts = ANDROID / "app" / "build.gradle.kts"
    groovy = ANDROID / "app" / "build.gradle"
    path = kts if kts.exists() else groovy
    if not path.exists():
        sys.exit("android/app/build.gradle(.kts) not found")
    s = path.read_text(encoding="utf-8")
    is_kts = path.suffix == ".kts"
    s = re.sub(r'(applicationId\s*=?\s*)"[^"]*"', r'\1"' + APPLICATION_ID + '"', s, count=1)
    s = re.sub(r"(minSdk(?:Version)?\s*=?\s*)flutter\.minSdkVersion", r"\g<1>24", s)
    if "key.properties" not in s:
        if is_kts:
            s = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + s
            props = ('val keystoreProperties = Properties().apply {\n'
                     '    val f = rootProject.file("key.properties")\n'
                     '    if (f.exists()) load(FileInputStream(f))\n}\n\n')
            signing = ('    signingConfigs {\n        create("release") {\n'
                       '            if (keystoreProperties.getProperty("storeFile") != null) {\n'
                       '                storeFile = file(keystoreProperties.getProperty("storeFile"))\n'
                       '                storePassword = keystoreProperties.getProperty("storePassword")\n'
                       '                keyAlias = keystoreProperties.getProperty("keyAlias")\n'
                       '                keyPassword = keystoreProperties.getProperty("keyPassword")\n'
                       '            }\n        }\n    }\n')
            use = ('signingConfig = if (keystoreProperties.getProperty("storeFile") != null) '
                   'signingConfigs.getByName("release") else signingConfigs.getByName("debug")')
            s = re.sub(r"^(android\s*\{)", lambda m: props + m.group(1) + "\n" + signing, s, count=1, flags=re.M)
            s = s.replace('signingConfig = signingConfigs.getByName("debug")', use, 1)
        else:
            head = ('def keystoreProperties = new Properties()\n'
                    'def keystorePropertiesFile = rootProject.file("key.properties")\n'
                    'if (keystorePropertiesFile.exists()) { keystoreProperties.load(new FileInputStream(keystorePropertiesFile)) }\n\n')
            signing = ('    signingConfigs {\n        release {\n'
                       '            if (keystoreProperties["storeFile"]) {\n'
                       '                storeFile file(keystoreProperties["storeFile"])\n'
                       '                storePassword keystoreProperties["storePassword"]\n'
                       '                keyAlias keystoreProperties["keyAlias"]\n'
                       '                keyPassword keystoreProperties["keyPassword"]\n'
                       '            }\n        }\n    }\n')
            use = 'signingConfig keystoreProperties["storeFile"] ? signingConfigs.release : signingConfigs.debug'
            s = head + s
            s = re.sub(r"(android\s*\{)", r"\1\n" + signing, s, count=1)
            s = s.replace("signingConfig signingConfigs.debug", use, 1)
        print(f"  {path.name}: applicationId {APPLICATION_ID}, minSdk 24, release signing from key.properties")
    path.write_text(s, encoding="utf-8")


def main() -> None:
    if not MANIFEST.exists():
        sys.exit("android/ missing - run first:  flutter create --org app.parvandeh --project-name admin_panel --platforms android .")
    patch_manifest()
    patch_activity()
    patch_styles()
    patch_gradle()
    subprocess.run([sys.executable, str(ROOT / "tools" / "make_icon.py"), str(MAIN / "res")], check=True)
    print("android/ is ready")


if __name__ == "__main__":
    main()
