#!/usr/bin/env python3
"""Prepares the generated android/ folder for a release (safe to run many times).

    python3 tools/patch_android.py

- AndroidManifest.xml: INTERNET (release builds can't go online without it), Persian app name,
  notification permissions and the receivers that bring scheduled reminders back after a reboot.
- app/build.gradle(.kts): core library desugaring, which flutter_local_notifications needs.
"""
from __future__ import annotations

import re
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


def patch_manifest() -> None:
    s = MANIFEST.read_text(encoding="utf-8")
    for perm in PERMISSIONS:
        if perm not in s:
            s = s.replace("<application", f'<uses-permission android:name="{perm}"/>\n    <application', 1)
            print(f"  manifest: + {perm}")
    s = s.replace('android:label="the_case"', 'android:label="پرونده"')
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
    path.write_text(s, encoding="utf-8")


def main() -> None:
    if not MANIFEST.exists():
        sys.exit("Android project missing - run first:  flutter create --org ir.aminsalem --project-name the_case --platforms android .")
    patch_manifest()
    patch_gradle()
    print("android/ is ready")


if __name__ == "__main__":
    main()
