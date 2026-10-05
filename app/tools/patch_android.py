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

PROGUARD = """# Myket in-app billing (the plugin reads purchases with Gson; keep their fields)
-keep class ir.myket.billingclient.** { *; }
-keep class ir.mservices.myketiap.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature, *Annotation*
"""


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
        sys.exit("Android project missing - run first:  flutter create --org ir.aminsalem --project-name the_case --platforms android .")
    patch_manifest()
    patch_gradle()
    copy_icons()
    print("android/ is ready")


if __name__ == "__main__":
    main()
