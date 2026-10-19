#!/usr/bin/env python3
"""Prepares the generated android/ folder for a release (safe to run many times).

    python3 tools/patch_android.py

- AndroidManifest.xml: INTERNET (release builds can't go online without it), Persian app name,
  notification permissions and the receivers that bring scheduled reminders back after a reboot.
- app/build.gradle(.kts): core library desugaring, which flutter_local_notifications needs.
- Myket in-app billing: manifest placeholders the myket_iap plugin needs, ProGuard keep rules.
- Release signing from android/key.properties (your permanent upload key) when it exists.
- res/: the launcher icon (adaptive + themed), the notification icon (tools/launcher/res, made by render.py).
"""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
MANIFEST = APP / "android" / "app" / "src" / "main" / "AndroidManifest.xml"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    # Cafe Bazaar in-app billing (Poolakey's own manifest declares it too; stating it here makes sure it is there)
    "com.farsitel.bazaar.permission.PAY_THROUGH_BAZAAR",
]

RECEIVERS = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""

DESUGAR_LIB = "com.android.tools:desugar_jdk_libs:2.1.4"


LINK_QUERIES = """    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
    </queries>
"""

# Android 11+ package visibility: without this the app cannot see (or bind to) the Cafe Bazaar app
BAZAAR_QUERIES = """    <queries>
        <package android:name="com.farsitel.bazaar" />
    </queries>
"""

BAZAAR_PROGUARD = """# Cafe Bazaar in-app billing (Poolakey binds to Bazaar's AIDL service and parses its answers; R8 must not strip it)
-keep class ir.cafebazaar.poolakey.** { *; }
-keep class ir.cafebazaar.flutter_poolakey.** { *; }
-keep class com.farsitel.bazaar.** { *; }
-dontwarn ir.cafebazaar.poolakey.**
"""

PROGUARD = """# Myket in-app billing (the plugin reads purchases with Gson; keep their fields)
-keep class ir.myket.billingclient.** { *; }
-keep class ir.mservices.myketiap.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature, *Annotation*
"""


# the permanent store package name: reverse of gammly.ir + the game. Never change it after publishing.
APPLICATION_ID = "ir.gammly.parvandeh"


def patch_screen_capture() -> None:
    """Secure every generated game build. Fail rather than silently ship an unsupported unprotected host."""
    main = APP / "android" / "app" / "src" / "main"
    activities = [p for folder in (main / "kotlin", main / "java")
                  for pattern in ("MainActivity.kt", "MainActivity.java") for p in folder.rglob(pattern)]
    if len(activities) != 1:
        raise RuntimeError("Expected one generated MainActivity for secure-window protection")
    activity = activities[0]
    source = activity.read_text(encoding="utf-8")
    package = re.search(r"^\s*package\s+([A-Za-z_][\w.]*)", source, re.M)
    if package is None:
        raise RuntimeError("MainActivity package missing")
    namespace = package.group(1)
    kotlin = activity.suffix == ".kt"
    base = r"(class\s+MainActivity\s*:\s*)(?:io\.flutter\.embedding\.android\.)?FlutterActivity(\s*\(\s*\))" if kotlin else r"(class\s+MainActivity\s+extends\s+)(?:io\.flutter\.embedding\.android\.)?FlutterActivity\b"
    if re.search(base, source):
        source = re.sub(base, lambda m: m.group(1) + "SecureFlutterActivity" + (m.group(2) if kotlin else ""), source, count=1)
    elif not re.search(r"class\s+MainActivity\s*(?::|extends)\s*SecureFlutterActivity\b", source):
        raise RuntimeError("Unsupported MainActivity superclass: adapt secure host explicitly before release")
    manifest = MANIFEST.read_text(encoding="utf-8")
    tag = re.search(r"<application\b[^>]*>", manifest, re.S)
    if tag is None:
        raise RuntimeError("Android application tag missing")
    name = re.search(r'android:name\s*=\s*"([^"]+)"', tag.group())
    secure_name = namespace + ".SecureGameApplication"
    if name and name.group(1) not in ("${applicationName}", "android.app.Application", secure_name):
        raise RuntimeError("Custom Application found: integrate secure lifecycle callbacks without replacing it")
    protected_tag = (tag.group()[:name.start(1)] + secure_name + tag.group()[name.end(1):] if name else
                     tag.group().replace("<application", f'<application android:name="{secure_name}"', 1))
    templates = Path(__file__).resolve().parent / "android"
    generated = {p.name: p.read_text(encoding="utf-8").replace("__PACKAGE__", namespace)
                 for p in templates.glob("Secure*.java")}
    if set(generated) != {"SecureGameWindows.java", "SecureGameApplication.java", "SecureFlutterActivity.java"}:
        raise RuntimeError("Secure-window source templates missing")
    destination = main / "java" / Path(*namespace.split("."))
    destination.mkdir(parents=True, exist_ok=True)
    for name, code in generated.items():
        (destination / name).write_text(code, encoding="utf-8")
    activity.write_text(source, encoding="utf-8")
    MANIFEST.write_text(manifest[:tag.start()] + protected_tag + manifest[tag.end():], encoding="utf-8")
    print("  Android: secure game windows, lifecycle and recents protection")


def patch_manifest() -> None:
    s = MANIFEST.read_text(encoding="utf-8")
    for perm in PERMISSIONS:
        if perm not in s:
            s = s.replace("<application", f'<uses-permission android:name="{perm}"/>\n    <application', 1)
            print(f"  manifest: + {perm}")
    s = s.replace('android:label="the_case"', 'android:label="پرونده"')
    if 'android:scheme="https"' not in s:
        s = s.replace("</manifest>", LINK_QUERIES + "</manifest>", 1)
        print("  manifest: + https link query (privacy page)")
    if 'android:name="com.farsitel.bazaar"' not in s:
        s = s.replace("</manifest>", BAZAAR_QUERIES + "</manifest>", 1)
        print("  manifest: + Cafe Bazaar package query")
    if "ScheduledNotificationReceiver" not in s:
        s = s.replace("</application>", RECEIVERS.lstrip("\n") + "    </application>", 1)
        print("  manifest: + reminder receivers")
    MANIFEST.write_text(s, encoding="utf-8")


def patch_gradle() -> None:
    kts = APP / "android" / "app" / "build.gradle.kts"
    groovy = APP / "android" / "app" / "build.gradle"
    path = kts if kts.exists() else groovy
    if not path.exists():
        sys.exit("android/app/build.gradle(.kts) not found")
    s = path.read_text(encoding="utf-8")
    is_kts = path.suffix == ".kts"
    flag = "isCoreLibraryDesugaringEnabled = true" if is_kts else "coreLibraryDesugaringEnabled true"
    if "oreLibraryDesugaringEnabled" not in s:
        if re.search(r"compileOptions\s*\{", s):
            s = re.sub(r"(compileOptions\s*\{)", r"\1\n        " + flag, s, count=1)
        else:
            s = re.sub(r"(android\s*\{)", r"\1\n    compileOptions {\n        " + flag + r"\n    }", s, count=1)
        print(f"  {path.name}: + desugaring")
    if DESUGAR_LIB not in s:
        dep = f'coreLibraryDesugaring("{DESUGAR_LIB}")' if is_kts else f"coreLibraryDesugaring '{DESUGAR_LIB}'"
        if re.search(r"^dependencies\s*\{", s, re.M):
            s = re.sub(r"^(dependencies\s*\{)", r"\1\n    " + dep, s, count=1, flags=re.M)
        else:
            s = s.rstrip() + f"\n\ndependencies {{\n    {dep}\n}}\n"
        print(f"  {path.name}: + {DESUGAR_LIB}")
    # the store package name (applicationId); `namespace` stays what flutter create made (code only)
    new_id = re.sub(r'(applicationId\s*=?\s*)"[^"]*"', r'\1"' + APPLICATION_ID + '"', s, count=1)
    if new_id != s:
        s = new_id
        print(f"  {path.name}: applicationId = {APPLICATION_ID}")
    # Myket billing: the plugin's manifest uses these placeholders
    if "marketApplicationId" not in s:
        if is_kts:
            ph = ('manifestPlaceholders += mapOf("marketApplicationId" to "ir.mservices.market", '
                  '"marketBindAddress" to "ir.mservices.market.InAppBillingService.BIND", '
                  '"marketPermission" to "ir.mservices.market.BILLING")')
        else:
            ph = ('manifestPlaceholders += [marketApplicationId: "ir.mservices.market", '
                  'marketBindAddress: "ir.mservices.market.InAppBillingService.BIND", '
                  'marketPermission: "ir.mservices.market.BILLING"]')
        s = re.sub(r"(defaultConfig\s*\{)", r"\1\n        " + ph, s, count=1)
        print(f"  {path.name}: + Myket manifest placeholders")
    # release signing with android/key.properties, and our ProGuard rules
    if "key.properties" not in s:
        if is_kts:
            imports = 'import java.util.Properties\nimport java.io.FileInputStream\n\n'
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
                   'signingConfigs.getByName("release") else signingConfigs.getByName("debug")\n'
                   '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")')
            s = imports + s  # imports may come before plugins {}; statements may not
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
            use = ('signingConfig keystoreProperties["storeFile"] ? signingConfigs.release : signingConfigs.debug\n'
                   '            proguardFiles getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"')
            s = head + s
            s = re.sub(r"(android\s*\{)", r"\1\n" + signing, s, count=1)
            s = s.replace("signingConfig signingConfigs.debug", use, 1)
        print(f"  {path.name}: + release signing from key.properties, ProGuard rules")
    path.write_text(s, encoding="utf-8")
    rules = path.parent / "proguard-rules.pro"
    if not rules.exists() or "myket" not in rules.read_text(encoding="utf-8"):
        with rules.open("a", encoding="utf-8") as f:
            f.write(PROGUARD)
        print("  proguard-rules.pro: + Myket keep rules")
    if "cafebazaar.poolakey" not in rules.read_text(encoding="utf-8"):
        with rules.open("a", encoding="utf-8") as f:
            f.write("\n" + BAZAAR_PROGUARD)
        print("  proguard-rules.pro: + Cafe Bazaar keep rules")


def copy_icons() -> None:
    src = APP / "tools" / "launcher" / "res"
    dst = APP / "android" / "app" / "src" / "main" / "res"
    n = 0
    for f in src.rglob("*"):
        if f.is_file():
            target = dst / f.relative_to(src)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, target)
            n += 1
    print(f"  res: {n} icon files copied")


def main() -> None:
    if not MANIFEST.exists():
        sys.exit("Android project missing - run first:  flutter create --org ir.gammly --project-name the_case --platforms android .")
    patch_manifest()
    patch_gradle()
    patch_screen_capture()
    copy_icons()
    print("android/ is ready")


if __name__ == "__main__":
    main()

