# Phase 0 Android Technical Spikes

This guide implements the five Android experiments from `PROJECT_BLUEPRINT.md` as isolated prototypes. It does not implement the parental-control product, backend, database, policy engine, or payment system.

The intended host is a physical Android phone connected to Nobara Linux by USB. Android Studio and Android emulator/system images are not required.

The five spikes must use separate application IDs and separate project directories. A failure, permission denial, manufacturer restriction, or VPN conflict in one spike must not affect the others.

## Ground rules

- Use an Android test phone or one for which you are authorised to manage the device.
- Do not use Device Owner provisioning on a phone you use as primary.
- Do not attempt Accessibility or overlay automation that bypasses user consent.
- Android 11+ package visibility means not every installed app is visible. Do not request `QUERY_ALL_PACKAGES` until the final store-use-case review.
- Android behaviour varies by version, OEM, and user settings. A result is evidence only for the tested device/Android build.
- “Can run on this phone” is different from “works across OEMs” and “passes Google Play policy review”.
- Use physical-device testing for all pass/fail decisions.

## Linux and SDK setup

Fedora/Nobara packages:

```bash
sudo dnf install -y git java-17-openjdk-devel android-tools unzip curl
java -version
adb --version
```

Install the SDK command-line tools without Android Studio:

```bash
mkdir -p "$HOME/Android/Sdk/cmdline-tools"
cd "$HOME/Downloads"
# Download commandlinetools-linux-*_latest.zip from
# https://developer.android.com/studio#command-line-tools-only
unzip -o commandlinetools-linux-*_latest.zip -d "$HOME/Android/Sdk/cmdline-tools"
mv "$HOME/Android/Sdk/cmdline-tools/cmdline-tools" \
  "$HOME/Android/Sdk/cmdline-tools/latest"
```

Add this to `~/.bashrc` or `~/.zshrc`, then reload the shell:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
```

Install only the packages needed for device builds:

```bash
yes | sdkmanager --licenses
sdkmanager \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0"
sdkmanager --list_installed
```

Use the compile/target SDK selected by the Expo SDK used in S-AND-5 instead of assuming an exact SDK. SDK 36 is a known blueprint baseline, not a reason to use an emulator.

Limit Gradle memory:

```bash
mkdir -p "$HOME/.gradle"
cat >> "$HOME/.gradle/gradle.properties" <<'EOF'
org.gradle.daemon=true
org.gradle.parallel=false
org.gradle.workers.max=2
org.gradle.caching=true
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m -XX:+UseSerialGC
kotlin.compiler.execution.strategy=in-process
android.useAndroidX=true
android.enableJetifier=false
EOF
```

Phone setup:

1. Enable Developer options by tapping **Settings > About phone > Build number** seven times.
2. Enable **USB debugging**.
3. Enable **Install via USB** or the OEM equivalent if available.
4. Connect the USB cable, accept the phone’s RSA prompt, and keep the phone unlocked.

```bash
echo 'SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:ff4200:*", TAG+="uaccess"' \
  | sudo tee /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
adb kill-server
adb start-server
adb devices
```

The result must show `device`, not `unauthorized`, `offline`, or an empty list.

## S-AND-1 — UsageStatsManager usage tracking

### Exact objective

Create a tiny native Android app that:

- checks and opens Usage Access settings;
- reads `UsageEvents` for the last 24 hours;
- logs `ACTIVITY_RESUMED` and `ACTIVITY_PAUSED` events;
- derives foreground sessions;
- compares its package counters with `dumpsys usagestats`.

### Technical uncertainty resolved

- whether `UsageStatsManager` exposes useful foreground events on the test Android/OEM combination;
- whether event timestamps and package names are consistent;
- whether missing, delayed, or batched events make per-app limits reliable;
- whether Usage Access survives reboot or app restart.

### Required Android permissions

- special app access `android.permission.PACKAGE_USAGE_STATS`; this is user-granted and cannot be requested by normal runtime permission API;
- `android.permission.QUERY_ALL_PACKAGES` is not required for this spike.

### Technologies/APIs

- Kotlin;
- Android View;
- `UsageStatsManager`;
- `UsageEvents`;
- `ACTIVITY_RESUMED`, `ACTIVITY_PAUSED`, and `ACTIVITY_STOPPED`;
- ADB `dumpsys usagestats`.

### Minimal folder structure

```text
spikes/s-and-1-usage/
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
└── app/
    ├── build.gradle.kts
    └── src/main/
        ├── AndroidManifest.xml
        └── java/com/guardly/spike/usage/
            └── MainActivity.kt
```

### Dependencies and installation

Use Gradle directly and no third-party dependencies. Create the project:

```bash
mkdir -p ~/GuardlySpikes/s-and-1-usage/app/src/main/java/com/guardly/spike/usage
cd ~/GuardlySpikes/s-and-1-usage
```

Create these files.

`settings.gradle.kts`:

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "S-AND-1-Usage"
include(":app")
```

`build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application") version "8.13.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
```

Pin versions to ones compatible with your installed JDK and SDK. If Gradle names a newer Android Gradle Plugin, accept that for your generated project only and record it.

`gradle.properties`:

```properties
org.gradle.daemon=true
org.gradle.parallel=false
org.gradle.workers.max=2
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m
android.useAndroidX=true
android.enableJetifier=false
reactNativeArchitectures=arm64-v8a
```

`app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.guardly.spike.usage"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.guardly.spike.usage"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures {
        viewBinding = true
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {}
```

`AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" />

    <application
        android:allowBackup="false"
        android:label="S-AND-1 Usage"
        android:theme="@android:style/Theme.Material.Light">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

`MainActivity.kt`:

```kotlin
package com.guardly.spike.usage

import android.app.AppOpsManager
import android.app.UsageEvents
import android.app.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    companion object {
        private const val TAG = "S_AND_1"
    }

    private lateinit var output: TextView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        val openSettings = Button(this).apply { text = "Open Usage Access settings" }
        val refresh = Button(this).apply { text = "Read usage events" }
        output = TextView(this)

        openSettings.setOnClickListener {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }
        refresh.setOnClickListener { refreshEvents() }

        root.addView(openSettings)
        root.addView(refresh)
        root.addView(output)
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        refreshEvents()
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun refreshEvents() {
        if (!hasUsageAccess()) {
            output.text = "USAGE ACCESS: denied\nTap the button, enable it for S-AND-1, then return."
            Log.w(TAG, "Usage access denied")
            return
        }

        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val start = end - 24L * 60L * 60L * 1000L
        val events = manager.queryEvents(start, end)
        val event = UsageEvents.Event()
        val rows = ArrayList<String>()
        var resumed = 0
        var paused = 0

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val typeName = when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> "RESUMED"
                UsageEvents.Event.ACTIVITY_PAUSED -> "PAUSED"
                UsageEvents.Event.ACTIVITY_STOPPED -> "STOPPED"
                else -> "TYPE_${event.eventType}"
            }
            if (event.eventType in setOf(
                    UsageEvents.Event.ACTIVITY_RESUMED,
                    UsageEvents.Event.ACTIVITY_PAUSED,
                    UsageEvents.Event.ACTIVITY_STOPPED
                )
            ) {
                val time = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
                    .format(Date(event.timeStamp))
                rows.add("$time $typeName ${event.packageName}")
                if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) resumed++
                if (event.eventType == UsageEvents.Event.ACTIVITY_PAUSED) paused++
                Log.i(TAG, "$typeName ${event.packageName} ${event.timeStamp}")
            }
        }

        val recent = rows.takeLast(100).joinToString("\n")
        output.text = "USAGE ACCESS: allowed\nRESUMED=$resumed PAUSED=$paused\n$recent"
    }
}
```

### Build and installation commands

```bash
cd ~/GuardlySpikes/s-and-1-usage
./gradlew wrapper --gradle-version 8.14.3
adb uninstall com.guardly.spike.usage || true
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.guardly.spike.usage/.MainActivity
```

### ADB debugging

```bash
adb logcat -c
adb logcat -s S_AND_1:I *:S
adb shell appops get com.guardly.spike.usage GET_USAGE_STATS
adb shell cmd appops set com.guardly.spike.usage GET_USAGE_STATS allow
adb shell dumpsys usagestats | head -100
adb shell am force-stop com.guardly.spike.usage
```

Do not use `cmd appops set ... allow` as a substitute for normal testing. The test verifies that the app’s grant path works; use the developer shortcut only if you need to reset or automate a test on a disposable device.

### Manual testing procedure

1. Launch the app.
2. Confirm the app reports denied usage access.
3. Open Usage Access settings and enable the app.
4. Return and confirm allowed.
5. Launch Chrome, wait 30 seconds, switch to Settings, wait 30 seconds.
6. Return to S-AND-1 and press refresh.
7. Close S-AND-1 completely and reopen it.
8. Repeat the test after reboot.
9. Compare package names and timestamps with `dumpsys usagestats`.

### Expected output

- explicit `USAGE ACCESS: allowed`;
- recent resumed/paused/stopped events in the UI;
- matching timestamps and package names in logcat;
- `dumpsys usagestats` contains the test packages.

### Common errors/troubleshooting

- `denied` after enabling: force-stop and reopen the spike, or reboot; then verify `appops get`.
- no Chrome event: wait 60 seconds and retest; some OEMs suppress duplicate or very brief events.
- package is present but timestamp is stale: event retention/OEM batching is not real-time.
- ADB shortcut has no effect: use the phone Settings UI and accept the app-ops restriction.
- Gradle missing SDK 36: run `sdkmanager "platforms;android-36" "build-tools;36.0.0"`.
- On a work/profile or managed device, Usage Access may be denied by policy.

### Known Android/OEM limitations

- Usage Access is a special app access that the user can revoke.
- Android may batch or delay events.
- event history has finite system retention.
- OEMs differ in resume/pause/stop reporting.
- Android 11+ restrictions also affect querying package names and app metadata.
- Android can return a launch event for a `LAUNCHER` intent while the app is not yet visible. Correlate with `ACTIVITY_RESUMED`, not package-launch alone.

### Acceptance criteria

Pass only if all apply:

- [ ] the permission-state UI distinguishes allowed and denied correctly;
- [ ] at least 10 foreground/resume transitions are observed on 2 test sessions;
- [ ] timestamps match within 5 seconds across app log and ADB dump;
- [ ] closing/reopening the app does not clear prior readings;
- [ ] reboot does not silently grant or revoke Usage Access;
- [ ] missing/batched event behaviour is written down for the tested phone.

---

## S-AND-2 — Detect blocked launches and show a blocking screen

### Exact objective

Detect that a fixed test package (for example Chrome) reaches the foreground and show a separate blocking Activity. Measure launch-to-block latency and test reliability with and without Accessibility.

The fixed test package must be chosen from a package the phone can safely demonstrate, then restored to normal use after the test.

### Technical uncertainty resolved

- most reliable permitted blocking method in Standard mode;
- latency and false-positive risk of polling versus Accessibility events;
- overlay permission and background-Activity-limit behaviour;
- reboot and recents behaviour.

### Required Android permissions

- `BIND_ACCESSIBILITY_SERVICE` for an accessibility service;
- `SYSTEM_ALERT_WINDOW` if testing an overlay;
- `PACKAGE_USAGE_STATS` if using UsageEvents polling as a fallback;
- `FOREGROUND_SERVICE` and an appropriate foreground-service type if the detector runs continuously;
- `POST_NOTIFICATIONS` on Android 13+ for a foreground-service notification.

The app must disclose consent before any special permission and provide an unblock/remove control.

### Technologies/APIs

- `AccessibilityService`;
- `AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED`;
- `UsageStatsManager` polling fallback;
- `SYSTEM_ALERT_WINDOW`;
- `WindowManager`;
- foreground service;
- `BlockActivity`.

### Permitted approaches

**Accessibility-first, Activity-second (recommended test)**

When a supported Window State Changed event names the blocked package, start `BlockActivity` using `FLAG_ACTIVITY_NEW_TASK`, `CLEAR_TOP`, and `NO_ANIMATION`.

Supported by Android when the Accessibility service is enabled. Subject to accessibility-event filtering/OEM delay and Play policy constraints. Do not use Accessibility for content scraping unrelated to enforcement.

**Overlay (supported only with explicit overlay permission)**

Draw a window above the target using `TYPE_APPLICATION_OVERLAY`. It is faster for a dedicated block screen on many devices but is intrusive and affected by one-time permissions, manufacturer overlay restrictions, and Android 14 foreground restrictions. The user can revoke it.

**Usage polling (best-effort fallback)**

Poll UsageEvents once per 1–2 seconds only while the screen is on. This is not a launch blocker; it is a detector. In Standard mode it can miss a brief launch and does not stop system-level use.

**Device Owner suspension (not used in this spike)**

`setPackagesSuspended` or `setApplicationHidden` is stronger but requires Device Owner setup and is not appropriate for a primary phone or mass-market Standard mode.

### Minimal folder structure

```text
spikes/s-and-2-block/
├── settings.gradle.kts
├── build.gradle.kts
└── app/src/main/
    ├── AndroidManifest.xml
    └── java/com/guardly/spike/block/
        ├── MainActivity.kt
        ├── BlockAccessibilityService.kt
        └── BlockActivity.kt
```

### Dependencies and installation

Use a standalone Android project with no third-party dependencies. Set `minSdk=26`, `targetSdk=36`, and package `com.guardly.spike.block`.

`AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="false"
        android:label="S-AND-2 Block">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".BlockActivity"
            android:excludeFromRecents="true"
            android:launchMode="singleTask"
            android:exported="false" />

        <service
            android:name=".BlockAccessibilityService"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_config" />
        </service>
    </application>
</manifest>
```

`res/xml/accessibility_config.xml`:

```xml
<accessibility-service
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/accessibility_description"
    android:accessibilityEventTypes="typeWindowStateChanged|typeWindowsChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:notificationTimeout="100"
    android:canRetrieveWindowContent="false"
    android:isAccessibilityTool="false"
    android:settingsActivity="com.guardly.spike.block.MainActivity" />
```

`res/values/strings.xml`:

```xml
<resources>
    <string name="accessibility_description">
        Demonstrates whether this device can show a block screen when a selected test app opens.
        It does not read message or screen content.
    </string>
</resources>
```

`MainActivity.kt`:

```kotlin
package com.guardly.spike.block

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val output = TextView(this)
        val open = Button(this).apply { text = "Enable Accessibility for S-AND-2" }
        open.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        root.addView(open)
        root.addView(output)
        setContentView(root)

        output.text = """
            Test target: com.android.chrome
            1. Enable Accessibility.
            2. Return to this app.
            3. Open Chrome.
            4. Return with the Back button.
        """.trimIndent()
    }
}
```

`BlockAccessibilityService.kt`:

```kotlin
package com.guardly.spike.block

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class BlockAccessibilityService : AccessibilityService() {
    companion object {
        const val TAG = "S_AND_2"
        const val BLOCKED_PACKAGE = "com.android.chrome"
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event?.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) return

        val packageName = event.packageName?.toString()
        if (packageName != BLOCKED_PACKAGE) return

        Log.i(TAG, "blocked-package foreground: $packageName at ${System.currentTimeMillis()}")
        val intent = Intent(this, BlockActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            )
            putExtra("blockedPackage", packageName)
        }
        startActivity(intent)
    }

    override fun onInterrupt() = Unit
}
```

`BlockActivity.kt`:

```kotlin
package com.guardly.spike.block

import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity

class BlockActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val packageName = intent.getStringExtra("blockedPackage") ?: "unknown"
        val output = TextView(this).apply {
            text = "BLOCKED\n$packageName"
            textSize = 24f
        }
        val close = Button(this).apply { text = "Close block screen" }
        close.setOnClickListener { finishAndRemoveTask() }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        root.addView(output)
        root.addView(close)
        setContentView(root)
    }
}
```

### Build and installation

```bash
cd ~/GuardlySpikes/s-and-2-block
./gradlew assembleDebug
adb uninstall com.guardly.spike.block || true
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.guardly.spike.block/.MainActivity
```

### ADB debugging

```bash
adb logcat -c
adb logcat -s S_AND_2:I *:S AndroidRuntime:E
adb shell am start -a android.settings.ACCESSIBILITY_SETTINGS
adb shell dumpsys accessibility | grep -A8 -B3 "com.guardly.spike.block"
adb shell am force-stop com.guardly.spike.block
```

### Manual testing procedure

1. Install the app and enable Accessibility.
2. Open Chrome; expect the block Activity.
3. Press Back/close and reopen Chrome five times.
4. Stop the app from recents and repeat.
5. Reboot, enable/disable Accessibility, and repeat.
6. Test while the screen is on, locked, and in battery saver.
7. Record one run with the phone recording timestamp and logcat timestamp.

For overlay testing, separately request the overlay permission and implement a toast-sized `TYPE_APPLICATION_OVERLAY` window only after the Accessibility test. Do not test both mechanisms simultaneously without recording which is responsible.

### Expected output

- Chrome is replaced by or obscured by the block screen;
- logcat records the package and timestamp;
- closing the block screen does not crash or relaunch Chrome;
- after reboot, the service only works if Accessibility remains enabled.

### Common errors/troubleshooting

- Accessibility service not listed: inspect `ANDROIDManifest.xml` and `accessibility_config.xml` resources.
- service cannot start Chrome because the app is still active: clear the Chrome task or press Home before launching.
- Block Activity is slow or not visible: background Activity starts are restricted; test overlay as a separate comparison.
- service disappears after force-stop: Android does not promise restart for an app that was force-stopped.
- OEM Accessibility is disabled by battery optimisation or background policy.
- opening Chrome by notification, shortcut, or external app can produce the first frame before the event.

### Known Android/OEM limitations

- Standard mode is reactive; a prohibited app may be visible briefly.
- Accessibility event timing is not guaranteed.
- Android 10+ background Activity starts can prevent reliable replacement.
- overlays can cover system surfaces and are restricted.
- OEMs may disable Accessibility or kill the app.
- Device admin and package suspension are stronger, but require enhanced provisioning and are not used here.

### Acceptance criteria

Pass only if all apply:

- [ ] normal user consent enables Accessibility;
- [ ] Chrome is replaced or blocked in at least 8 of 10 launches;
- [ ] median launch-to-block is measured and documented;
- [ ] worst launch latency is documented;
- [ ] no normal app content is read or logged;
- [ ] service disable/permission revoke is recoverable;
- [ ] the guide identifies overlay vs Accessibility as the chosen candidate.

---

## S-AND-3 — Background execution, persistence, screen-off and reboot

### Exact objective

Run a minimal native foreground service with a Boot Completed receiver, verify persistence after app closure, screen-off behaviour, Doze/battery modes, force-stop, and reboot.

This spike establishes whether the architecture can rely on native enforcement or needs OEM-specific exceptions. It does not claim a universal 24-hour result.

### Technical uncertainty resolved

- whether a foreground service survives screen-off and app closure;
- whether the Boot Completed receiver starts it;
- which battery/OEM settings terminate it;
- how quickly the app heartbeat resumes after reboot.

### Required Android permissions

- `RECEIVE_BOOT_COMPLETED`;
- `FOREGROUND_SERVICE`;
- `FOREGROUND_SERVICE_SPECIAL_USE` or the relevant Android-version foreground type;
- `POST_NOTIFICATIONS` on Android 13+;
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is not requested in this spike; it is a sensitive permission and should not be part of the MVP entitlement claim.

### Technologies/APIs

- `Service`;
- `startForeground`;
- notification channel;
- `BroadcastReceiver`;
- `ACTION_BOOT_COMPLETED`;
- `ACTION_SCREEN_ON/OFF`;
- `AlarmManager` is not needed for a coarse heartbeat;
- Android battery settings and Doze.

### Minimal folder structure

```text
spikes/s-and-3-survival/
├── settings.gradle.kts
├── build.gradle.kts
└── app/src/main/
    ├── AndroidManifest.xml
    ├── java/com/guardly/spike/survival/
    │   ├── MainActivity.kt
    │   ├── HeartbeatService.kt
    │   └── BootReceiver.kt
    └── res/values/strings.xml
```

### Dependencies and installation

No third-party dependencies.

`AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="false"
        android:label="S-AND-3 Survival">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <receiver
            android:name=".BootReceiver"
            android:enabled="true"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>

        <service
            android:name=".HeartbeatService"
            android:exported="false"
            android:foregroundServiceType="specialUse" />
    </application>
</manifest>
```

`MainActivity.kt`:

```kotlin
package com.guardly.spike.survival

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { startService() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val start = Button(this).apply { text = "Start heartbeat" }
        start.setOnClickListener { requestPermissionAndStart() }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        root.addView(start)
        setContentView(root)
    }

    private fun requestPermissionAndStart() {
        if (Build.VERSION.SDK_INT >= 33) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            startService()
        }
    }

    private fun startService() {
        val intent = Intent(this, HeartbeatService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }
}
```

`HeartbeatService.kt`:

```kotlin
package com.guardly.spike.survival

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

class HeartbeatService : Service() {
    companion object {
        const val TAG = "S_AND_3"
        const val CHANNEL_ID = "guardly_spike"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var heartbeat = 0L

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.i(TAG, "screen=" + intent.action)
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            heartbeat++
            val uptime = android.os.SystemClock.elapsedRealtime()
            Log.i(TAG, "heartbeat=$heartbeat uptime=$uptime screen=${isScreenOn()}")
            handler.postDelayed(this, 60_000)
        }
    }

    private fun isScreenOn(): Boolean =
        (getSystemService(Context.POWER_SERVICE) as android.os.PowerManager).isInteractive

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("S-AND-3 heartbeat")
            .setContentText("Foreground service test")
            .setOngoing(true)
            .build()
        startForeground(1, notification)

        registerReceiver(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            }
        )
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        unregisterReceiver(screenReceiver)
        Log.w(TAG, "service destroyed heartbeat=$heartbeat")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Phase 0 heartbeat",
            NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
```

`BootReceiver.kt`:

```kotlin
package com.guardly.spike.survival

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) return

        Log.i("S_AND_3", "boot received")
        ContextCompat.startForegroundService(
            context,
            Intent(context, HeartbeatService::class.java)
        )
    }
}
```

### Build and installation

```bash
cd ~/GuardlySpikes/s-and-3-survival
./gradlew assembleDebug
adb uninstall com.guardly.spike.survival || true
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.guardly.spike.survival/.MainActivity
```

### ADB debugging

```bash
adb logcat -c
adb logcat -s S_AND_3:I *:S AndroidRuntime:E
adb shell dumpsys activity services com.guardly.spike.survival
adb shell dumpsys deviceidle
adb shell am broadcast -a android.intent.action.BOOT_COMPLETED
adb shell am force-stop com.guardly.spike.survival
adb shell cmd activity get-uid-state com.guardly.spike.survival
adb reboot
```

Boot broadcast from ADB is not equivalent to reboot. Use a real reboot for acceptance.

### Manual testing procedure

1. Start the foreground service and verify the notification.
2. Swipe the app away from recents.
3. Record one-minute heartbeat values for 30 minutes.
4. Turn the screen off for 30 minutes.
5. Enable battery saver and leave Doze to test.
6. Force-stop from settings and verify Android behaviour.
7. Reboot by holding the device power controls.
8. Lock the phone and wait for unlock.
9. Open OEM battery settings and test restrictive options.
10. Repeat on OEM modes for 24 hours if possible.

### Expected output

- persistent foreground notification;
- 60-second log heartbeats;
- screen actions logged;
- reboot starts the service if the implementation and OEM allow;
- force-stop must be detected as a hard kill, not silently recovered.

### Common errors/troubleshooting

- service fails immediately on Android 12+: declare an approved foreground type and notification.
- boot receiver never fires: reboot is required; OEM boot receivers may be delayed.
- heartbeat stops: read battery optimisation logs and `dumpsys deviceidle`.
- notification permission denied: Android 13+ shows no foreground service notification but service may still start; UX and product policy require it.
- service is not restartable after force-stop: Android semantics; this is a known stop state until user opens the app or grants a later boot context.
- WorkManager is not a substitute for a continuous enforcement loop.

### Known Android/OEM limitations

- `START_STICKY` does not guarantee immediate or exact restart.
- OEMs can stop services and remove alarms.
- boot receivers can be delayed or disabled.
- force-stop is generally a strong user action and app-restarter assumptions must stop.
- Doze/network and App Standby do not necessarily stop foreground services, but may suppress networking.
- manufacturer battery modes are outside application guarantees.

### Acceptance criteria

Pass only if all apply:

- [ ] service remains present for 30 screen-off minutes;
- [ ] app closure by recents does not stop the service;
- [ ] reboot recovery is measured as a timestamp;
- [ ] battery saver/Doze result is written down;
- [ ] force-stop is documented as unsupported or relaunch-dependent;
- [ ] OEM battery allowlisting steps are reproduced if required;
- [ ] no claim is made beyond what this physical phone proves.

---

## S-AND-4 — Basic website blocking with Android VpnService and DNS filtering

### Exact objective

Start a minimal Android `VpnService`, pass normal DNS traffic through to the network, then block one exact domain with NXDOMAIN. This spike first proves pass-through before a blocklist is introduced.

Use `example.com` initially. Do not test with arbitrary websites or captive enterprise networks in your first run.

### Technical uncertainty resolved

- whether local TUN/DNS interception works on the test phone;
- IPv4 and UDP/53 parsing requirements;
- whether Chrome/Firefox use plain DNS or secure/private DNS;
- whether private DNS, DoH, and DoT bypass this local DNS filter;
- whether concurrent VPN apps interfere.

### Required Android permissions

- `android.permission.INTERNET`;
- `android.permission.FOREGROUND_SERVICE`;
- `android.permission.FOREGROUND_SERVICE_SPECIAL_USE`;
- `android.permission.POST_NOTIFICATIONS`;
- runtime consent via `VpnService.prepare()`;
- VPN binding in manifest:
  `android.permission.BIND_VPN_SERVICE`.

No `QUERY_ALL_PACKAGES` permission is needed.

### Technologies/APIs

- `VpnService`;
- `ParcelFileDescriptor`;
- TUN interface;
- `DatagramSocket`;
- UDP/53 DNS packet parsing;
- Android VPN consent dialog;
- Chrome/Firefox manual test.

### Minimal folder structure

```text
spikes/s-and-4-dns-vpn/
├── settings.gradle.kts
├── build.gradle.kts
└── app/src/main/
    ├── AndroidManifest.xml
    └── java/com/guardly/spike/dns/
        ├── MainActivity.kt
        ├── DnsVpnService.kt
        └── DnsPacket.kt
```

### Dependencies and installation

No third-party dependencies for the pass-through spike.

`AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="false"
        android:label="S-AND-4 DNS VPN">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".DnsVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="true"
            android:foregroundServiceType="specialUse">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
    </application>
</manifest>
```

`MainActivity.kt`:

```kotlin
package com.guardly.spike.dns

import android.Manifest
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    companion object {
        const val BLOCKED_DOMAIN = "example.com"
    }

    private val vpnPermission =
        ActivityResultContracts.StartActivityForResult()

    private val vpnActivity =
        registerForActivityResult(vpnPermission) { result ->
            if (result.resultCode == RESULT_OK) startVpn()
        }

    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) requestVpn()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val start = Button(this).apply { text = "Start DNS VPN" }
        val stop = Button(this).apply { text = "Stop DNS VPN" }
        start.setOnClickListener { requestPermissionAndStart() }
        stop.setOnClickListener { stopService(Intent(this, DnsVpnService::class.java)) }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        root.addView(start)
        root.addView(stop)
        setContentView(root)
    }

    private fun requestPermissionAndStart() {
        if (Build.VERSION.SDK_INT >= 33) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            requestVpn()
        }
    }

    private fun requestVpn() {
        val consent = VpnService.prepare(this)
        if (consent != null) vpnActivity.launch(consent)
        else startVpn()
    }

    private fun startVpn() {
        val intent = Intent(this, DnsVpnService::class.java)
        ContextCompat.startForegroundService(this, intent)
        Toast.makeText(this, "Starting VPN", Toast.LENGTH_SHORT).show()
    }
}
```

`DnsPacket.kt`:

```kotlin
package com.guardly.spike.dns

import java.nio.ByteBuffer

object DnsPacket {
    fun parseQuestionName(packet: ByteArray, dnsOffset: Int): String? {
        if (dnsOffset + 12 > packet.size) return null
        val name = StringBuilder()
        var index = dnsOffset + 12
        while (index < packet.size) {
            val length = packet[index].toInt() and 0xff
            if (length == 0) break
            if (length > 63 || index + 1 + length > packet.size) return null
            if (name.isNotEmpty()) name.append('.')
            name.append(String(packet, index + 1, length, Charsets.US_ASCII))
            index += length + 1
        }
        return name.toString().lowercase()
    }

    fun buildNxdomain(original: ByteArray): ByteArray {
        val copy = original.copyOf()
        if (copy.size < 12) return copy
        val buffer = ByteBuffer.wrap(copy)
        buffer.putShort(2, buffer.getShort(2).toInt().or(0x8080).toShort())
        val flags = buffer.getShort(2).toInt()
        val ancount = 0
        buffer.putShort(6, ancount.toShort())
        buffer.putShort(8, 0)
        buffer.putShort(10, 0)
        return copy
    }
}
```

`DnsVpnService.kt`:

```kotlin
package com.guardly.spike.dns

import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class DnsVpnService : VpnService() {
    companion object {
        const val TAG = "S_AND_4"
        const val BLOCKED_DOMAIN = "example.com"
        const val CHANNEL_ID = "s_and_4_dns"
    }

    private var tun: ParcelFileDescriptor? = null
    private var socket: DatagramSocket? = null
    private val running = AtomicBoolean(false)
    private var worker: Thread? = null

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        if (running.get()) return START_STICKY
        startNotification()

        val builder = Builder()
            .setSession("S-AND-4 DNS pass-through")
            .addAddress("10.0.2.2", 32)
            .addDnsServer("1.1.1.1")
            .addRoute("0.0.0.0", 0)
            .setMtu(1500)

        tun = builder.establish()
        if (tun == null) {
            Log.e(TAG, "VPN builder.establish() returned null")
            stopSelf()
            return START_NOT_STICKY
        }

        socket = DatagramSocket().also { protect(it) }
        running.set(true)
        worker = thread(name = "dns-tun-worker", start = true) { processTun() }
        Log.i(TAG, "VPN established")
        return START_STICKY
    }

    private fun processTun() {
        val fd = tun!!.fileDescriptor
        val input = java.io.FileInputStream(fd)
        val output = java.io.FileOutputStream(fd)
        val packet = ByteArray(32767)
        val readSocket = socket!!

        while (running.get()) {
            val size = try { input.read(packet) } catch (_: Exception) { -1 }
            if (size <= 0) continue

            val ipv4HeaderLength = (packet[0].toInt() and 0x0f) * 4
            if (ipv4HeaderLength < 20 || size < ipv4HeaderLength + 8) continue
            if ((packet[9].toInt() and 0xff) != 17) continue

            val udpOffset = ipv4HeaderLength
            val udpLength = ((packet[udpOffset + 4].toInt() and 0xff) shl 8) +
                (packet[udpOffset + 5].toInt() and 0xff)
            val dnsOffset = udpOffset + 8
            val dnsLength = udpLength - 8
            if (dnsLength <= 12 || dnsOffset + dnsLength > size) continue

            val destinationPort =
                ((packet[udpOffset + 2].toInt() and 0xff) shl 8) +
                    (packet[udpOffset + 3].toInt() and 0xff)
            if (destinationPort != 53) continue

            val dnsRequest = packet.copyOfRange(dnsOffset, dnsOffset + dnsLength)
            val name = DnsPacket.parseQuestionName(dnsRequest, 0)
            Log.i(TAG, "DNS query=$name")

            val sourceIp = packet.copyOfRange(12, 16)
            val destIp = packet.copyOfRange(16, 20)
            val sourcePort =
                ((packet[udpOffset].toInt() and 0xff) shl 8) +
                    (packet[udpOffset + 1].toInt() and 0xff)

            val dnsResponse = if (name == BLOCKED_DOMAIN || name?.endsWith(".$BLOCKED_DOMAIN") == true) {
                DnsPacket.buildNxdomain(dnsRequest)
            } else {
                val upstream = DatagramPacket(dnsRequest, dnsRequest.size)
                upstream.address = InetAddress.getByName("1.1.1.1")
                upstream.port = 53
                readSocket.send(upstream)
                val reply = DatagramPacket(ByteArray(4096), 4096)
                readSocket.soTimeout = 3000
                try {
                    readSocket.receive(reply)
                    reply.data.copyOf(reply.length)
                } catch (_: Exception) {
                    null
                }
            }

            dnsResponse?.let { response ->
                val udpLengthResponse = response.size + 8
                val ipHeaderLength = ipv4HeaderLength
                val full = ByteArray(ipHeaderLength + udpLengthResponse)
                packet.copyInto(full, 0, 0, ipHeaderLength)

                val ip = ByteBuffer.wrap(full)
                ip.put(0, 0x45)
                ip.putShort(2, full.size.toShort())
                ip.put(8, 64)
                ip.position(ipHeaderLength)

                System.arraycopy(destIp, 0, full, 12, 4)
                System.arraycopy(sourceIp, 0, full, 16, 4)

                full[ipHeaderLength] = ((sourcePort shr 8) and 0xff).toByte()
                full[ipHeaderLength + 1] = (sourcePort and 0xff).toByte()
                full[ipHeaderLength + 2] = ((destinationPort shr 8) and 0xff).toByte()
                full[ipHeaderLength + 3] = (destinationPort and 0xff).toByte()
                full[ipHeaderLength + 4] = ((udpLengthResponse shr 8) and 0xff).toByte()
                full[ipHeaderLength + 5] = (udpLengthResponse and 0xff).toByte()
                full[ipHeaderLength + 6] = 0
                full[ipHeaderLength + 7] = 0
                response.copyInto(full, ipHeaderLength + 8)

                output.write(full)
            }
        }
    }

    private fun startNotification() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "S-AND-4 DNS VPN",
            NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("S-AND-4 DNS VPN")
            .setContentText("Test VPN active")
            .setOngoing(true)
            .build()
        startForeground(2, notification)
    }

    override fun onRevoke() {
        stopVpn()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun stopVpn() {
        running.set(false)
        worker?.interrupt()
        socket?.close()
        tun?.close()
        tun = null
    }
}
```

This code is a verification scaffold. Its pass-through is intentionally IPv4-only and UDP-only. It has no TCP/53 support and no IPv6 route. It is not production-ready.

The IP rewrite section must be checksum-recomputed for a real packet implementation. Before declaring pass-through reliable, replace the scaffold with a vetted packet library or a stable VPN/DNS library; do not ship hand-assembled DNS responses that leave stale IP/UDP checksums. This spike’s correct outcome may be “pass-through can work, but packet implementation is too risky and needs a library”.

### Build and installation

```bash
cd ~/GuardlySpikes/s-and-4-dns-vpn
./gradlew assembleDebug
adb uninstall com.guardly.spike.dns || true
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.guardly.spike.dns/.MainActivity
```

### ADB debugging

```bash
adb logcat -c
adb logcat -s S_AND_4:I *:S AndroidRuntime:E
adb shell dumpsys connectivity | grep -A20 -i vpn
adb shell settings get global private_dns_mode
adb shell settings get global private_dns_specifier
adb shell dumpsys netd
```

### Manual testing procedure

1. Start the app and accept the Android VPN consent.
2. Confirm the VPN key appears in the status bar.
3. Open Chrome and verify a normal domain loads.
4. Open a private/incognito window and try `http://example.com`.
5. A DNS block should produce NXDOMAIN or a block/connection error.
6. Test the same domain in Firefox.
7. Test with Private DNS set to Automatic and to a provider hostname.
8. Enable Android secure DNS inside Chrome and retest.
9. Try Wi-Fi, mobile data, VPN conflict, and reboot.
10. Disable the app VPN from settings and retest.

### Expected output

- pass-through: normal DNS and HTTPS pages load;
- block: `example.com` does not open;
- logcat shows a DNS query and the exact domain;
- Android displays an active VPN key and prompt;
- VPN is reversible from settings.

### Common errors/troubleshooting

- VPN consent returns cancelled: the phone has an existing VPN owner or VPN policy; revoke the existing app and retry.
- no network after connect: route/MTU/packet return path is wrong; stop the VPN immediately and verify mobile/Wi-Fi route.
- only UDP/53 works: DNS over TCP/TLS is expected to bypass or fail, depending on browser.
- captive portal fails: add a known captive-portal bypass for testing or stop the VPN.
- Private DNS bypasses the filter: document this as expected limitation, not a pass.
- Chrome does not use Android plain DNS: test Chrome Secure DNS settings and DoH.

### Known Android/OEM limitations

- only one VPN app can own the VpnService tunnel.
- Android Private DNS and browser DoH can bypass plain DNS.
- Android 11+ may change VPN routes and notifications.
- Work-managed devices can block VpnService.
- OEMs may preserve or disconnect VPNs differently after reboot.
- Device Owner always-on VPN is not tested on a primary phone.
- DNS filtering only demonstrates domain resolution; it cannot identify every HTTPS SNI or in-app custom resolver.

### Acceptance criteria

Pass only if all apply:

- [ ] normal DNS pass-through works for at least 3 domains;
- [ ] `example.com` is blocked by exact-domain NXDOMAIN;
- [ ] subdomains are tested and explicitly accepted or rejected;
- [ ] Chrome and Firefox behaviour is recorded;
- [ ] Secure DNS/Private DNS bypasses are documented;
- [ ] VPN stop/revoke restores normal networking immediately;
- [ ] the implementation is classified as a pass-through DNS proof, not a production filter.

---

## S-AND-5 — Call native Kotlin from React Native through an Expo local module

### Exact objective

Build a physical-device Expo development build that calls a local Expo module implemented in Kotlin and returns a plain result to React Native.

This is a native bridge spike only. It does not include an Expo config plugin, service, VPN, or product policy.

### Technical uncertainty resolved

- whether the selected Expo SDK and local module API build on Linux;
- whether local Expo modules work with Gradle and a physical phone;
- whether the New Architecture bridge works with Kotlin;
- whether changes are rebuilt with or without prebuild;
- whether Expo Go is avoided successfully.

### Required Android permissions

- None. The bridge itself requires no Android permission.
- USB/debugging is required only for build/install.

### Technologies/APIs

- Expo CLI;
- Expo development build;
- Expo Modules API;
- Kotlin `expo.modules.kotlin.modules.Module`;
- React Native/TypeScript;
- Metro;
- Gradle.

### Minimal folder structure

```text
spikes/s-and-5-expo-module/
├── app.config.ts
├── App.tsx
├── package.json
├── modules/
│   └── guardly-native/
│       ├── expo-module.config.json
│       ├── index.ts
│       ├── src/
│       ├── android/build.gradle
│       └── android/src/main/java/
│           └── expo/modules/guardlynative/
│               └── GuardlyNativeModule.kt
└── android/  # generated by prebuild
```

Do not commit `android/` in the final architecture unless native files become difficult to regenerate. For this spike, retaining `android/` until it passes is acceptable.

### Dependencies and installation

Install Node 22 and Bun:

```bash
curl -fsSL https://fnm.vercel.app/install | bash
exec $SHELL
fnm install 22
fnm default 22
curl -fsSL https://bun.sh/install | bash
exec $SHELL
node -v
bun -v
```

Create the isolated app:

```bash
mkdir -p ~/GuardlySpikes
cd ~/GuardlySpikes
bunx create-expo-app s-and-5-expo-module --template blank-typescript
cd s-and-5-expo-module
bunx expo install expo-dev-client
bunx expo-module create --local guardly-native
```

If `expo-module create --local` is unavailable in the installed CLI, use the exact command shown by:

```bash
bunx create-expo-module --help
```

Pin the SDK by keeping its generated versions. Do not replace Expo packages with random npm versions.

### Essential module files

`modules/guardly-native/expo-module.config.json`:

```json
{
  "platforms": ["android"],
  "android": {
    "modules": ["expo.modules.guardlynative.GuardlyNativeModule"]
  }
}
```

`modules/guardly-native/index.ts`:

```ts
import GuardlyNativeModule from "./src/GuardlyNativeModule";

export function getNativeStatus(): Promise<string> {
  return GuardlyNativeModule.getNativeStatus();
}

export function addNative(left: number, right: number): Promise<number> {
  return GuardlyNativeModule.addNative(left, right);
}
```

`modules/guardly-native/src/GuardlyNativeModule.ts`:

```ts
import { requireNativeModule } from "expo";

type GuardlyNative = {
  getNativeStatus(): Promise<string>;
  addNative(left: number, right: number): Promise<number>;
};

export default requireNativeModule<GuardlyNative>("GuardlyNative");
```

`GuardlyNativeModule.kt`:

```kotlin
package expo.modules.guardlynative

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class GuardlyNativeModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("GuardlyNative")

        AsyncFunction("getNativeStatus") {
            "Kotlin says: Native bridge works"
        }

        AsyncFunction("addNative") { left: Int, right: Int ->
            left + right
        }
    }
}
```

`App.tsx`:

```tsx
import { useState } from "react";
import { Button, StyleSheet, Text, View } from "react-native";
import { addNative, getNativeStatus } from "./modules/guardly-native";

export default function App() {
  const [output, setOutput] = useState("Tap to test native Kotlin");

  async function testBridge() {
    try {
      const status = await getNativeStatus();
      const sum = await addNative(17, 25);
      setOutput(`${status}\n17 + 25 = ${sum}`);
    } catch (error) {
      setOutput(error instanceof Error ? error.message : String(error));
    }
  }

  return (
    <View style={styles.container}>
      <Text style={styles.output}>{output}</Text>
      <Button title="Call Kotlin" onPress={testBridge} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  output: {
    marginBottom: 24,
    textAlign: "center",
  },
});
```

### Build and installation

Generate native Android files:

```bash
cd ~/GuardlySpikes/s-and-5-expo-module
bunx expo prebuild --platform android --clean
```

Limit native ABIs for development if the project template allows:

```properties
reactNativeArchitectures=arm64-v8a
```

Set the generated `android/gradle.properties` if it differs from this setting.

Build and install via USB:

```bash
adb devices
bunx expo run:android --device
```

This must build a debug development APK. Expo Go must not be used.

Later JavaScript-only changes:

```bash
adb reverse tcp:8081 tcp:8081
bunx expo start --dev-client
```

If the Metro menu is not available in a terminal, launch the app from the phone and confirm it is the development build, not Expo Go.

### ADB debugging

```bash
adb logcat -c
adb logcat -s ReactNativeJS:I ExpoModulesCore:I AndroidRuntime:E
adb shell pm list packages | grep expo
adb shell pidof -s com.guardly.spike.expo
adb shell dumpsys package com.guardly.spike.expo | grep -i native
```

Use `adb logcat | grep Guardly` after adding a Kotlin `Log.i` line for a native-call test.

### Manual testing procedure

1. Install the development build.
2. Disconnect Metro and verify the app still opens.
3. Open Metro and press the native bridge button.
4. Confirm the status and sum.
5. Kill the app and reopen it.
6. Stop Metro and confirm the bridge still works in the installed debug build.
7. Rebuild only after changing Kotlin code.
8. Change the Kotlin return string, rebuild, and confirm the JS UI sees the new value.

### Expected output

```text
Kotlin says: Native bridge works
17 + 25 = 42
```

The app package must be the development build package and the bridge must resolve by the exact module name `GuardlyNative`.

### Common errors/troubleshooting

- `Cannot find native module GuardlyNative`: run prebuild and rebuild; Expo local modules are absent from Expo Go.
- Kotlin class not discovered: verify `expo-module.config.json` package/class spelling.
- Gradle package mismatch: verify namespace and module folder package align.
- build fails due to memory: set JVM 2 GB and worker count 2; stop Gradle after testing.
- build fails due to SDK mismatch: let Expo template pin compile SDK and accept only its documented NDK/SDK requirement.
- Metro cannot connect: run `adb reverse tcp:8081 tcp:8081`.
- Development build starts but JS is stale: press `r` or reload the app.
- Expo module export missing: restart Metro after adding the module.

### Known Android/OEM limitations

- Expo Go cannot execute local native modules.
- JavaScript-only changes require Metro reload; Kotlin changes require an APK rebuild.
- New Architecture type mapping is not guaranteed across unsupported Expo SDK pairs.
- Debug builds can differ from release builds in Metro, architecture, and signing.
- USB installation can be blocked by OEM “Install via USB”.

### Acceptance criteria

Pass only if all apply:

- [ ] app opens as an Expo development build, not Expo Go;
- [ ] a Kotlin `String` returns into React Native;
- [ ] a Kotlin `Int` or numeric calculation returns correctly;
- [ ] native/Kotlin changes require and receive a rebuild;
- [ ] the app reconnects through Metro over USB;
- [ ] the module works after app restart;
- [ ] no Expo Go fallback is recorded as a pass.

---

## Recommended execution order

1. **S-AND-5** — proves the Linux toolchain, Expo dev build, and local native bridge with the lowest risk.
2. **S-AND-1** — proves usage events and test-time ADB comparison.
3. **S-AND-3** — tests native service and reboot behaviour independently.
4. **S-AND-2** — tests launch detection only after the native and event APIs are understood.
5. **S-AND-4** — tests the VPN tunnel last because it can interfere with networking and VPN state.

Run S-AND-4 last: stopping it must restore the device’s normal network before moving to the next test.

## Result record checklist

Create `docs/spikes/` and record one dated text/Markdown file per spike. Do not place private device identifiers or secrets in the repository.

For each spike, record:

- [ ] phone manufacturer and model;
- [ ] Android version and security patch;
- [ ] exact build/Expo/Gradle versions;
- [ ] permissions granted and permission-state screenshots;
- [ ] pass/fail;
- [ ] exact observed latency or uptime;
- [ ] ADB/logcat evidence;
- [ ] OEM battery/VPN/accessibility settings;
- [ ] reboot result;
- [ ] known bypass or failure mode;
- [ ] whether the result is supported, blocked, or unreliable;
- [ ] recommended architecture decision;
- [ ] Go/no-go reason.

Suggested final decision matrix:

| Spike | Technical result | Recommended action |
|---|---|---|
| S-AND-1 | usage event quality on tested phone | proceed or narrow accuracy claims |
| S-AND-2 | Accessibility/overlay/reactive blocking latency | choose one permitted approach |
| S-AND-3 | service and reboot survival | document OEM constraints |
| S-AND-4 | DNS pass-through and bypasses | go/no-go for MVP filtering |
| S-AND-5 | Expo local Kotlin bridge | use or replace local module boundary |

Do not start full product implementation until all five spikes have a written Go, Conditional Go, or No-Go decision and the failures are attributed to a specific Android/API/OEM limitation rather than a skipped test.