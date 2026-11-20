# PROJECT_BLUEPRINT.md — Cross-Platform Parental Control Ecosystem

> **Document status:** v1.0 — written 19 Nov 2026.
> **Audience:** a solo developer (Nobara Linux, 8 GB RAM, Ryzen 3 5300U, physical Android device, no Mac yet).
> **How to read this:** Sections 1–4 define *what* and *why*. Sections 5–11 define *how it is built*. Sections 12–15 are *tooling and research*. Section 16 is the *build order*. Sections 17–20 cover practice, cost, risks and references.
>
> **Verification legend used throughout**
> - ✅ **Verified** — checked against a primary/official or repository source during preparation of this document.
> - 🟡 **From knowledge, re-verify** — I am confident in the concept, but numbers/versions/policy wording change often. Check the linked official doc before depending on it.
> - ⚠️ **Risk / limitation** — something that can block or invalidate a feature.
>
> I did **not** have a way to run code or test devices while writing this. Every API behaviour described is from documentation/knowledge and must be proven by the spikes listed in Phase 0.

---

## Table of Contents

0. [Executive Summary and Changes to the Proposed Stack](#0-executive-summary-and-changes-to-the-proposed-stack)
1. [Project Overview, Scope and MVP Definition](#1-project-overview-scope-and-mvp-definition)
2. [Development Environment and Hardware Constraints](#2-development-environment-and-hardware-constraints)
3. [Technology Stack — Critical Evaluation](#3-technology-stack--critical-evaluation)
4. [Functional Requirements and Platform Feasibility](#4-functional-requirements-and-platform-feasibility)
5. [System Architecture](#5-system-architecture)
6. [Policy Engine](#6-policy-engine)
7. [Database Design](#7-database-design)
8. [API Architecture](#8-api-architecture)
9. [Real-Time Communication and Synchronisation](#9-real-time-communication-and-synchronisation)
10. [Security and Privacy](#10-security-and-privacy)
11. [Scalability and Performance](#11-scalability-and-performance)
12. [Open-Source Project Research](#12-open-source-project-research)
13. [Development Environment Setup (Nobara Linux)](#13-development-environment-setup-nobara-linux)
14. [Monorepo and Folder Structure](#14-monorepo-and-folder-structure)
15. [Testing Strategy](#15-testing-strategy)
16. [Development Roadmap and Milestones](#16-development-roadmap-and-milestones)
17. [Documentation and Engineering Practices](#17-documentation-and-engineering-practices)
18. [Cost Analysis](#18-cost-analysis)
19. [Risks, Assumptions and Unresolved Technical Decisions](#19-risks-assumptions-and-unresolved-technical-decisions)
20. [References and Official Documentation](#20-references-and-official-documentation)

---

## 0. Executive Summary and Changes to the Proposed Stack

### 0.1 The product in one paragraph

A parent defines **one platform-independent policy per child**. The backend validates and versions it, then **compiles** it into a per-device configuration according to what that device can actually enforce (the `DeviceCapability` model). Each child device **enforces locally and offline** with native code (Kotlin on Android, Swift/Screen Time APIs on iOS, a Manifest V3 extension on desktop browsers), reports usage/blocked attempts in batches, and acknowledges the policy version it applied. Parents see the result in a React Native app and a React web dashboard.

### 0.2 The five most important engineering truths (read these first)

1. **Enforcement must never depend on the network or on the JavaScript runtime.** Android may kill your app, OEMs aggressively restrict background work, and React Native's JS engine is not a reliable place to run a blocking loop. The child app is *React Native UI on top of a pure-Kotlin enforcement engine* that works with the JS runtime dead.
2. **Android gives ordinary apps limited power.** Without Device Owner (DPC) status, a child with Settings access can usually uninstall, force-stop or revoke permissions. You must design for two tiers — **Standard mode** (store-installable, bypassable by a determined child, tamper *detection* and parent alerts) and **Enhanced mode** (Device Owner, provisioned by factory reset/QR or ADB, much harder to bypass, not suitable for Play Store mass-market install). ✅ The open-source TimeLimit app itself hides its device-owner features in its Play Store build behind a `storeCompilant` build flag (see §12).
3. **iOS is a different product, not a port.** Apple's Screen Time APIs deliberately hide raw data: apps/sites are opaque tokens, usage is rendered in a sandboxed extension that cannot send data to your server, and no browsing history is available. The **Family Controls distribution entitlement needs Apple approval** (community reports range from ~3 weeks to many months ✅ Apple forum threads) — **request it in Phase 0**, not Phase 12.
4. **Website blocking on Android is hard and has no single answer.** Realistic options: VpnService-based local DNS filtering (user can switch it off unless Device Owner always-on VPN is used), Accessibility-based URL reading in browsers (Play-policy risky and brittle), or Device-Owner-managed browser policies. The MVP ships DNS filtering via VpnService and is honest about its bypasses.
5. **Do not build microservices.** A modular monolith on Node/Express/Postgres with a Postgres-backed job queue handles private beta comfortably and gives clear split lines later.

### 0.3 Changes I recommend to your proposed technology choices

| # | Your proposal | Recommendation | Justification |
|---|---|---|---|
| 1 | Separate `apps/android-child` and `apps/ios-child` | **One Expo app `apps/child-mobile`** with two *local Expo modules* (`modules/enforcement-android` in Kotlin, `modules/enforcement-ios` in Swift) | ~80 % of the UI (onboarding, permission guide, pairing, status, PIN) is identical. Two apps double UI work. Native code stays separate per platform inside one JS UI. Android remains first-class; the iOS module is simply absent from Android builds. |
| 2 | Redis "when justified" | **No Redis in MVP.** Use **pg-boss** (Postgres-backed queue) for jobs and Postgres for rate-limit counters initially | Saves RAM on 8 GB dev machine and a service to host. Add Redis only when (a) running >1 API instance needing shared rate-limits/WebSocket fan-out, or (b) queue contention shows in metrics. |
| 3 | Turborepo | **Bun workspaces first; add Turborepo later** | Task caching matters for CI and many packages. With ~6 packages and a 3-person-at-most team, Bun workspaces + root scripts are enough. Turborepo is easy to add later because it only reads `package.json` scripts. |
| 4 | Bun as runtime | **Bun as package manager/workspace tool; run API on Node 22 LTS** (optionally Bun for scripts) | Prisma, Metro/Expo, Gradle tooling and many native tools assume Node. Using Bun to *install* is low risk; using it as the *production runtime* for Express+Prisma+ws adds an unneeded variable. 🟡 Re-test if you want Bun runtime later. |
| 5 | Expo "Go" | **Expo development builds (`expo-dev-client`) from day one for child app**, config plugins + local Expo modules. Parent app *can* use Expo Go during early UI work only if it uses no custom native modules | Expo Go cannot load custom native code (AccessibilityService, VpnService, FamilyControls). |
| 6 | Android child via "native Kotlin modules" for everything | Kotlin **services** (foreground service, AccessibilityService, VpnService, FCM receiver, DeviceAdminReceiver) own enforcement; Expo module is only a **thin bridge** (get status, open settings, push new policy, read local stats) | Prevents the JS thread from being a single point of failure. |
| 7 | Recharts | Keep Recharts for the **web dashboard**. For parent mobile use `react-native-svg` + a light chart lib or victory-native 🟡 | Recharts is DOM/SVG-based and does not run in React Native. |
| 8 | REST + WebSockets | **REST as source of truth; FCM/APNs as wake-up; WebSocket only for foreground sessions** (parent dashboard live view, child app foreground) | Mobile OSes kill idle sockets. See §9. |
| 9 | `ActivityEvent` generic table | **Typed tables** (`AppUsageSession`, `WebsiteVisit`, `BlockedAttempt`) plus an `IngestBatch` idempotency table; no generic raw-event table in MVP | One generic JSON event table is easy to write and painful to query/aggregate. Typed tables index well and partition cleanly. |
| 10 | Child as a user account | **Children have profiles, not logins.** Devices authenticate as devices | Data minimisation; no child credentials to leak; simpler consent model. |

### 0.4 Recommended build order in one line

Backend + auth → family/child/device pairing → minimal parent web → **Android child skeleton on a physical device** → native usage stats → app blocking → DNS filtering → policy sync with offline enforcement → analytics → browser extension → iOS (after Mac + entitlement) → hardening.

---

## 1. Project Overview, Scope and MVP Definition

### 1.1 Components

| # | Component | Technology | MVP? |
|---|---|---|---|
| 1 | Backend API (modular monolith) | Node 22, TypeScript, Express 5, Prisma, PostgreSQL, ws, pino, zod, pg-boss | **Yes** |
| 2 | Parent web dashboard | React + Vite + TS + Tailwind + Recharts | **Yes** (first parent UI) |
| 3 | Parent mobile app | Expo (React Native) + TS | Phase after web; thin MVP |
| 4 | Child app (Android) | Expo dev-build + Kotlin enforcement engine | **Yes** (flagship) |
| 5 | Child app (iOS) | Same Expo app + Swift Screen Time module + extensions | **Later** (needs Mac + entitlement) |
| 6 | Browser extension | MV3 TypeScript (Chrome/Edge; Firefox build target) | Post-Android-MVP |
| 7 | Shared packages | `shared-types`, `validation`, `policy-contracts`, `api-client` | **Yes** |

### 1.2 MVP vs future

**MVP ("portfolio-demonstrable", Android-first):**
- Parent registration/login, one family, multiple children, QR/code pairing, device list with online/offline.
- Android Standard mode: usage stats, per-app block, per-app daily limit, total daily limit, bedtime schedule, DNS-based domain blocking (blocklist + allowlist), blocked-attempt log, permission-health detection, tamper/offline alerts.
- Policy versioning, FCM wake-up + pull, ack, offline enforcement from signed cached policy.
- Daily/weekly usage charts, blocked attempts, device health.
- Temporary time extension ("+30 minutes") from the parent app.

**Post-MVP (explicitly deferred):**
- Android Enhanced (Device Owner) mode; category-based web filtering at scale; school-time presets; multiple guardians with role matrix; Firefox build; iOS; monthly trends; notification digest emails; app-category auto-classification beyond a seed catalogue; native desktop agent.

**Out of scope forever (by design, not capability):** keylogging, secret screenshots, message/call/SMS content interception, hidden/stealth mode, location tracking (not requested; if added later, it needs its own consent design), anything that hides the app from the child. Monitoring must be visible and explained to the child on-device.

### 1.3 Core domain vocabulary

- **Family** — tenancy boundary; all data is scoped by `familyId`.
- **Guardian** — a `User` with a role in a family (`OWNER`, `GUARDIAN`, optional `VIEWER`).
- **ChildProfile** — a person being supervised; owns the policy and the aggregates.
- **Device** — a physical device or browser installation tied to one child profile.
- **Policy** — the parent's intent for a child (platform-independent). **PolicyVersion** — immutable snapshot.
- **Compiled policy** — a per-device, capability-filtered, signed rendering of a PolicyVersion.
- **Enforcement tier** — `STANDARD` | `DEVICE_OWNER` (Android); `SCREEN_TIME_CHILD` (iOS); `BROWSER_ONLY` (desktop).

---

## 2. Development Environment and Hardware Constraints

The full command-level guide is **§13**. This section records the *design consequences* of your hardware.

| Constraint | Consequence in this blueprint |
|---|---|
| 8 GB RAM, Ryzen 3 5300U (4C/8T) | Never run IDE + emulator + Gradle daemon + Postgres in Docker + Metro + browser at once. Budget in §13.9. Use **native Postgres via dnf**, not Docker. One Gradle daemon capped at ~2 GB. |
| No Android Studio / emulator | Everything uses **cmdline-tools + platform-tools + physical device**. Expo local builds (`expo run:android`) call Gradle directly. |
| Linux only | Android: 100 % doable. Browser extension: 100 %. Backend/web: 100 %. **iOS: Xcode, signing, Simulator, device deployment require macOS.** See §13.11 for the path. |
| Bun preference | Bun for install/workspaces/scripts; Node 22 for API runtime (§0.3 #4). |
| VS Code or Neovim | Kotlin editing works via `fwcd/kotlin-language-server` (🟡 adequate, weaker than Android Studio) or the official JetBrains Kotlin LSP (🟡 early stage). Keep native Kotlin **small and well-tested** so you rarely need heavy IDE refactoring. |

**Design rule derived from the hardware:** put as much logic as possible into **pure-Kotlin, JVM-testable classes** (the policy evaluator, usage interval merger, schedule math). Those can be unit-tested with `./gradlew testDebugUnitTest` on the host JVM with no device and no emulator.

---

## 3. Technology Stack — Critical Evaluation

### 3.1 Backend

| Choice | Verdict | Notes |
|---|---|---|
| Node.js 22 LTS + TypeScript | ✅ Keep | Matches your PERN skills. |
| Express 5 | ✅ Keep | 🟡 Express 5 is the default `latest` on npm; it handles rejected promises in async handlers natively — remove `express-async-errors`-style hacks. |
| PostgreSQL | ✅ Keep | Use `jsonb` for policy documents, native partitioning later. |
| Prisma | ✅ Keep with caveats | 🟡 Newer Prisma majors changed config (`prisma.config.ts`) and engine/driver-adapter setup — follow the current Prisma docs when you scaffold. **Partitioned tables, partial indexes and some constraints need hand-written SQL migrations**; Prisma can still query them as ordinary models if the model's `@@id` includes the partition key. |
| Zod | ✅ Keep | Shared in `packages/validation`; infer TS types from schemas to avoid drift. |
| REST | ✅ Keep | OpenAPI generated from Zod via `zod-to-openapi` 🟡 (optional). |
| WebSockets (`ws`) | ✅ Keep, narrow scope | Foreground-only (§9). Do not use socket.io unless you need its fallbacks; `ws` is smaller and enough. |
| Pino | ✅ Keep | `pino-http` for request logs; redact tokens/PINs/codes. |
| Redis | ❌ Defer | See §0.3 #2. |
| **Add: pg-boss** | ✅ Add | Postgres-backed jobs: aggregation, retention purge, notification fan-out. Zero extra infra. |
| **Add: argon2** (`@node-rs/argon2` or `argon2`) | ✅ Add | Password and pairing-code hashing. |
| **Add: jose** | ✅ Add | JWT/JWS (access tokens, signed compiled policies). |
| **Add: firebase-admin** | ✅ Add | Send FCM data messages (free). |

### 3.2 Parent web dashboard
React + Vite (not Next.js — no SSR need, lighter on 8 GB) + TypeScript + Tailwind + Recharts + TanStack Query. ✅

### 3.3 Parent mobile
Expo + TypeScript + Expo Router + TanStack Query + `expo-notifications` + `expo-secure-store`. The parent app requests **no sensitive Android permissions**, which keeps its Play review simple. **Keep it a separate store listing from the child app** — their permission/policy profiles are completely different (parent app: none; child app: usage access, accessibility, VPN, device admin).

### 3.4 Android child — evaluation of "RN + Expo + Kotlin"

**Verdict: viable, with strict boundaries.**

Expo concepts you will use ✅/🟡:
- **Development builds** (`expo-dev-client`): your own debug APK containing your native code. Install via USB. Expo Go is not used for the child app.
- **Prebuild / Continuous Native Generation**: `npx expo prebuild` generates `android/` from `app.config.ts` + config plugins. Decide early: **commit `android/`** (recommended for this project because you will hand-edit manifests/services) or regenerate each time (cleaner but your Kotlin must then live entirely in local modules + config plugins). **Recommendation:** keep native code in `modules/enforcement-android/` (a *local Expo module*, created with `npx create-expo-module --local`) and use a **config plugin** only for manifest entries; do not commit generated `android/` so upgrades stay manageable. If this proves painful, switch to committed `android/` — record it as an ADR.
- **Expo Modules API (Kotlin)**: write bridge `Module` definitions; keep services in plain Android classes registered by the plugin in `AndroidManifest.xml`.
- **New Architecture**: ✅ Expo SDK 55+ / RN 0.83+ support **only** the New Architecture (Legacy dropped; SDK 54 was the last with Legacy). ✅ SDK 56 released 22 May 2026 with RN 0.85 and React 19.2. 🟡 A vendor changelog dated Sept 2026 references an "Expo SDK 57 / RN 0.86" baseline, so a newer SDK may exist: run `bun create expo-app` and take whatever is current, then **pin it** and upgrade deliberately (Expo advises not to adopt New Architecture and a new SDK simultaneously — a non-issue for a new project).

Boundary contract (strict):

```
┌─────────────── React Native (JS) ───────────────┐
│ UI, onboarding, pairing, PIN screen, charts,    │
│ settings. May be dead/killed at any moment.     │
└───────────────▲─────────────────────────────────┘
                │ Expo module bridge (thin, async, idempotent)
┌───────────────┴─────────────────────────────────┐
│ Kotlin: EnforcementEngine (pure), PolicyStore    │
│ (Room/SQLite), UsageCollector, BlockOverlay,     │
│ AccessibilityService, VpnService, FCM service,   │
│ DeviceAdminReceiver, SyncWorker (WorkManager)    │
│ Owns enforcement. Never needs JS to run.         │
└──────────────────────────────────────────────────┘
```

### 3.5 iOS child
RN UI + Swift module + **three extensions** (DeviceActivityMonitor, ShieldConfiguration, ShieldAction) and optionally DeviceActivityReport. Extensions are separate targets with their own memory limits; they are created in Xcode and must be added to the Expo project via a config plugin or committed `ios/` folder (🟡 community plugins exist; evaluate before writing your own). Requires macOS, Apple Developer Program, and the Family Controls entitlement. Details in §4.C.

### 3.6 Desktop extension
TypeScript + MV3 + `declarativeNetRequest` (DNR). Build with Vite + `@crxjs/vite-plugin` 🟡 or plain `esbuild`; keep build tooling minimal. Details in §4.D.

### 3.7 Monorepo
Bun workspaces. **Native build systems stay isolated**: Gradle/Xcode live inside each Expo app's generated `android/`/`ios/` folders and are never driven from the repo root. Shared code is *pure TypeScript only* (types, Zod schemas, policy contracts, API client). Metro needs `watchFolders`/workspace resolution for shared packages — Expo auto-configures monorepos in recent SDKs ✅ but verify with a "hello shared package" test in Phase 1.

---
## 4. Functional Requirements and Platform Feasibility

Requirement IDs (`FR-A-01` …) are stable and should be referenced from tests, ADRs and PR titles.

### A. Parent account and family management

| ID | Requirement | MVP | Notes |
|---|---|---|---|
| FR-A-01 | Register/login with email + password (argon2id) | ✅ | Email verification via SMTP (see §18). |
| FR-A-02 | Short-lived access token + rotating refresh token with reuse detection | ✅ | §10.1 |
| FR-A-03 | Create family; creator becomes `OWNER` | ✅ | |
| FR-A-04 | Multiple child profiles per family | ✅ | Name, birth year (not full DOB), avatar colour. Birth year drives age-appropriate defaults. |
| FR-A-05 | Invite additional guardians by email/code; roles `OWNER`/`GUARDIAN` | ⏭ | Data model supports it from day one. |
| FR-A-06 | Pair device by QR or one-time code | ✅ | §8, §10.4 |
| FR-A-07 | Device list with online/offline/stale status, last sync, capability summary | ✅ | Online = heartbeat within 2× interval. |
| FR-A-08 | Account settings, change password, delete account | ✅ | Deletion triggers retention purge (§7.9). |
| FR-A-09 | Password recovery by emailed single-use token | ✅ | Tokens hashed, 30-min expiry. |
| FR-A-10 | Revoke a device: server invalidates credentials, device wipes policy/data on next contact; parent alerted if device never confirms | ✅ | Revocation cannot *force* uninstall on Standard-mode Android. |

### B. Android child device — feasibility matrix

Legend: **S** = Standard mode (ordinary app, user-granted special accesses). **DO** = Device Owner mode. ✅/🟡/⚠️/❌.

| Feature | Mechanism | S | DO | Key limitations |
|---|---|---|---|---|
| View installed apps | `PackageManager.queryIntentActivities(LAUNCHER)` | 🟡 | ✅ | Android 11+ package visibility: declare `<queries>` for launcher intent (preferred) rather than `QUERY_ALL_PACKAGES`, which Google Play restricts to approved use-cases 🟡 verify whether "parental control" qualifies at submission time. |
| App usage duration | `UsageStatsManager` (`queryEvents` / `queryUsageStats`); special access `PACKAGE_USAGE_STATS` granted by user in Settings | ✅ | ✅ | `queryUsageStats` buckets are coarse; use `queryEvents` (`ACTIVITY_RESUMED/PAUSED`, API 29+) and build your own sessions. Data retention in system is limited (~days for events). Some OEMs omit or batch events. |
| Last-used app | Latest `ACTIVITY_RESUMED` event | ✅ | ✅ | Same as above. |
| Block selected apps | S: detect foreground app (UsageEvents polling and/or AccessibilityService window events) → show blocking Activity/overlay. DO: `setPackagesSuspended` (API 24+) / `setApplicationHidden` | 🟡 | ✅ | S-mode is *reactive* (a flash of the app can be visible) and subject to Android 10+ background-activity-start limits; needs overlay permission (`SYSTEM_ALERT_WINDOW`) or accessibility to reliably show the block screen. DO suspension is system-enforced. |
| Per-app daily limits | Local usage accumulation + evaluator → block when exceeded | ✅ | ✅ | Accuracy depends on foreground detection granularity (target ±1 min). |
| Total daily screen time | Sum of interactive foreground time excluding allowlisted apps (phone, dialer, emergency) | ✅ | ✅ | Define "screen time" precisely in ADR (§19). |
| Bedtime / school / custom schedules | Local schedule evaluation using device clock *corrected by server-time offset* | ✅ | ✅ | **Clock tampering**: child changes time/timezone. Mitigate: store server-time offset, listen to `ACTION_TIME_CHANGED`/`ACTION_TIMEZONE_CHANGED`, compare with `SystemClock.elapsedRealtime()`, flag and optionally lock. DO can `setAutoTimeRequired`/restrict date-time config 🟡. |
| Temporary extension | Server issues `PolicyException` → included in next compiled policy; FCM wake | ✅ | ✅ | Needs connectivity to grant; offline devices get it on reconnect. |
| Block websites (domain list) | Local `VpnService` DNS filter (null-routing/NXDOMAIN for blocked domains) | 🟡 | ✅ | Child can turn VPN off in Settings (S). DO can set always-on VPN (`setAlwaysOnVpnPackage`, lockdown). DoH/DoT in browsers (e.g. "Secure DNS", Private DNS) can bypass plain-DNS filtering unless handled (block known DoH endpoints, require system Private DNS off/forced). Only one VPN app active at a time. Play requires VPN to be core functionality with prominent disclosure. |
| Website categories | Domain→category lists (e.g. open blocklists, §12.3) compiled to a local lookup (hash set / bloom filter) | 🟡 | 🟡 | List licensing and size (memory!). Start with 5–10 coarse categories (adult, gambling, malware, social, games, streaming). |
| Allow-list (kid-safe-only) mode | DNS default-deny + allowed domains | 🟡 | ✅ | Breaks CDNs/third-party domains; needs a curated helper list. |
| Activity reports | Batches of sessions + aggregates | ✅ | ✅ | |
| Limit-reached alerts | Device event → backend → FCM/Expo push to parent | ✅ | ✅ | |
| Blocked-attempt log | Local append → batch upload | ✅ | ✅ | For DNS: log domain + timestamp only. |
| Detect permission disabled | Periodic check of: usage access (`AppOpsManager`), accessibility enabled (`Settings.Secure`), VPN active, overlay permission, notification permission, battery-optimisation exemption, device-admin active; report in heartbeat | ✅ | ✅ | If the app is force-stopped it cannot report; backend infers "stale" from missing heartbeats. |
| Connectivity issues | Heartbeat gaps ⇒ `STALE`/`OFFLINE` | ✅ | ✅ | Cannot distinguish "no internet" from "app killed". |
| Remote policy sync | §9 | ✅ | ✅ | |
| Uninstall protection | S: Device Admin (`BIND_DEVICE_ADMIN`; deactivation required before uninstall) — still works but is a legacy API; DO: `setUninstallBlocked` | 🟡 | ✅ | Child can deactivate admin unless protected by Settings restrictions; combine with PIN gate **inside our app** and tamper alerts. |

**Android-specific platform risks (all 🟡 — confirm on target API level):**
- **Foreground service types**: Android 14+ requires a declared `foregroundServiceType`; Android 15 added time limits on some types (e.g., `dataSync`). Use the type that matches the use-case and be ready to justify it in Play Console's foreground-service declaration.
- **Background activity launch** limits (Android 10+): you cannot freely start an Activity from the background; overlay permission or an Accessibility/full-screen-intent path is needed for the block screen.
- **Restricted settings (Android 13+)**: apps installed outside a store may have Accessibility and Notification-listener toggles greyed out until the user allows "restricted settings" in App Info. Test your sideloaded dev APK and your release path separately.
- **Exact alarms**: `SCHEDULE_EXACT_ALARM` is restricted; do **not** rely on exact alarms. Schedule boundaries are evaluated by the enforcement loop, plus inexact alarms/WorkManager as a backstop.
- **WorkManager periodic work minimum is 15 minutes**; it is a *backstop* for sync, never the enforcement path.
- **OEM battery managers** (Xiaomi/MIUI-HyperOS, Huawei, Oppo/Realme, Vivo, Samsung "sleeping apps"): can kill foreground services or block autostart. Maintain an OEM-guidance table in-app (dontkillmyapp.com style) and detect `isIgnoringBatteryOptimizations`. Test on the *actual* manufacturer of your test devices; behaviour varies widely.
- **Target API requirement for Play**: new/updated apps must target a recent API level (rolling yearly deadline) 🟡 verify current minimum in Play Console help.
- **Play Accessibility policy** 🟡: apps not designed primarily as accessibility tools must justify AccessibilityService use, must not use it for undisclosed data collection, and require prominent in-app disclosure + consent. Design so the product **still works (degraded) without Accessibility**, and treat Accessibility as an *optional strengthening* of app-blocking reliability (e.g., faster foreground detection, press-HOME on block). The TimeLimit privacy policy ✅ describes using accessibility only to press the Home button before showing the lock screen — a conservative pattern worth copying.

**Normal permissions vs Device Owner — explicit statement.** An ordinary app cannot: prevent its own uninstall without admin tricks, block Settings, suspend other packages, enforce always-on VPN, or lock the date/time. Those are DPC capabilities. **DO provisioning** requires either factory-reset setup (QR/NFC/zero-touch) or, for development only, `adb shell dpm set-device-owner <pkg>/<AdminReceiver>` on a device with **no accounts** ✅ (the TimeLimit-based parent-console wiki documents exactly this ADB flow). A consumer cannot be expected to factory-reset a phone, so **Enhanced mode is a "power-user / managed-device" option, not the default**.

### C. iOS child device — what Apple actually permits

Frameworks (✅ Apple Developer Documentation): **FamilyControls** (authorisation + opaque selection tokens), **ManagedSettings** (apply shields/restrictions), **DeviceActivity** (schedules, thresholds, monitor extension, report extension), **ManagedSettingsUI** (customise the shield screen).

| Capability | Possible? | Detail |
|---|---|---|
| Authorise as parental control for a **child** | ✅ | `AuthorizationCenter.shared.requestAuthorization(for: .child)` — requires a parent/guardian **in the same Family Sharing group** to approve on the child's device ✅. `.individual` (adult controlling own device) is a different mode. |
| Entitlement | ⚠️ | `com.apple.developer.family-controls`: development works with the dev capability; **distribution requires requesting permission via Apple's form** ✅; entitlement is tied to bundle IDs, and **each extension target needs it too** ✅ (forum reports of extensions stuck on development-only). Reported waits: ~3 weeks to several months ✅ (community reports; Apple gives no SLA). Approval is per bundle ID — plan bundle IDs carefully and don't change developer account ownership casually (forum reports duplicate Screen Time entries after transfer ✅). |
| Choose apps/categories/sites to restrict | ✅ with caveats | `FamilyActivityPicker` returns a `FamilyActivitySelection` of **opaque tokens**; you do **not** receive bundle IDs or names of the apps. Your own UI can render them only through Apple's `Label(token)` views. A parent configuring *remotely* from their own device is a known pain point: the selection must be made through Apple's picker, then the encoded selection forwarded to the child's app. 🟡 **Spike required** to prove token portability between parent and child devices for your team ID. Fallback: configure restrictions on the child's device with parent authentication (PIN/biometric). |
| Block/shield apps, categories, web domains | ✅ | `ManagedSettingsStore` (`shield.applications`, `shield.applicationCategories`, `shield.webDomains`, `webContent.blockedByFilter` etc.). Shields persist after your app exits; they are applied by the system. |
| Schedules and usage thresholds | ✅ | `DeviceActivityCenter.startMonitoring` with `DeviceActivitySchedule` and `DeviceActivityEvent` thresholds; **DeviceActivityMonitor extension** gets callbacks (`intervalDidStart`, `eventDidReachThreshold`, …) and can apply/clear shields **even if the app is not running**. Extensions run with tight CPU/memory budgets 🟡 (community reports ≈6 MB for the monitor extension) — keep them tiny, no heavy parsing. ⚠️ Community reports of false-positive threshold callbacks on iOS 26.2/26.3 ✅ (Apple forums, Jan 2026) — build tolerance and a re-check path. |
| Read per-app usage and send to your server | ❌ | Usage is displayed through **DeviceActivityReport** (SwiftUI in a sandboxed extension) and **cannot be exported to your backend**. You can learn only that *thresholds you defined* were reached. So the iOS dashboard will lack per-app minutes. Do not promise it. |
| Arbitrary browser history | ❌ | Not available. |
| Content filter extension (NEFilterControlProvider) for Screen Time apps | ⚠️ | Apple DTS confirmed on the forums that production content-filter save works for **`.child`** authorisation but not `.individual` ✅. Evaluate only after core shielding works. |
| Remote policy delivery | 🟡 | APNs silent pushes are throttled/not guaranteed; rely on: (a) next app launch, (b) background app refresh, (c) pushed alert notifications that prompt opening, (d) pre-scheduled DeviceActivity schedules containing the full week's rules so the child device enforces autonomously. |
| Simulator testing | ❌ | Treat Family Controls as **physical-device only**; Apple's own Family Sharing child account needed. |
| Distribution | ⚠️ | Apple Developer Program (USD 99/yr 🟡), App Review scrutiny of parental-control claims, privacy nutrition labels, Kids/Family guidelines. TestFlight external builds have been reported (✅ forum) to prompt for authorisation but not shield; test with an App Store–signed build early. |

**iOS feature promise for the blueprint:** shield selected apps/categories/domains; schedules (bedtime/school); daily limit thresholds; "limit reached" event to parent; parent-approved extension by changing the schedule/threshold; **no** per-app minute reporting to your backend; **no** history.

### D. Desktop browser extension

| Feature | Chrome/Edge (MV3) | Firefox | Notes |
|---|---|---|---|
| Block/allow sites | `declarativeNetRequest` dynamic rules (`chrome.declarativeNetRequest.updateDynamicRules`) — block, redirect to extension "blocked" page | ✅ DNR supported 🟡; Firefox MV3 also retains blocking `webRequest` | DNR rule count limits exist 🟡 (check current "dynamic rule" and "regex rule" quotas); use `requestDomains`/`urlFilter` rules, not many regexes. |
| Categories | Compile category→domain lists into DNR rulesets (static rules in manifest for big lists, dynamic for per-family overrides) | same | Static rulesets can be enabled/disabled at runtime 🟡. |
| Time-based rules | `chrome.alarms` + rule update; the service worker is ephemeral, so **persist state in `chrome.storage`** and recompute on every wake | Firefox MV3 uses **event pages** (`background.scripts`), not service workers 🟡 | Don't hold timers in memory. |
| View browsing activity | `chrome.webNavigation` (committed events) + `chrome.tabs` for title/URL + active-tab time via `chrome.idle` | Similar | Requires broad host permissions + `history`/`tabs`; needs prominent disclosure and Web Store justification. Incognito: extension is off by default; user must allow it. |
| Website usage estimates | Active-tab time with `idle` state and tab focus events; **estimate**, not exact | same | Label as estimate in UI. |
| Offline cache | Rules persist in storage; extension keeps working offline | same | |
| Remote sync | Poll via `chrome.alarms` (min ~30 s in packaged ext; 1 min typical) + optional WebSocket only while service worker alive — **do not depend on it** | same | |
| Prevent removal | Only through **enterprise policy** (`ExtensionInstallForcelist`, `IncognitoModeAvailability`) on managed OS profiles | Firefox policies.json | A child with admin rights can remove or use another browser. State this plainly in UI. |

**Browser-level vs system-wide:** the extension controls *one browser profile*. It cannot block native desktop apps, other browsers, or other profiles. System-wide control needs a **native desktop agent** (Windows service / macOS Network Extension + Screen Time / Linux), which is future work. Architect the sync protocol and `Device` model so a future agent is just another `platform` value.

### E. Parent dashboard and analytics

- Family overview (children, devices, status chips).
- Child page: today's screen time vs limit, top apps, blocked attempts, domain blocks.
- Charts: today by hour, 7-day by day, 30-day trend, category split.
- History: date-range filter, device filter.
- Health: per-device capabilities, missing permissions, last sync, applied vs desired policy version.
- Notifications centre.

**Aggregation without double counting (normative rule):**
1. **Device screen time = sum of foreground app sessions on that device** (Android: `AppUsageSession`; desktop: *not available* via extension, only browser active time).
2. **Website visits are a breakdown *inside* a browser app session**, never added to screen time. For Android, `WebsiteVisit` rows (if any) are annotated with `parentSessionId` or at least the browser package; reports show them in a separate "Web activity" panel.
3. **Per-child total = sum over devices** of device screen time, but overlapping wall-clock time across devices is **allowed** (child can use tablet and phone concurrently — show both, and also show "wall-clock active time" as max-coverage union if you want). Store aggregates per device and derive the child view.
4. **Desktop extension time** is stored as `source = BROWSER_EXTENSION` aggregates and reported as "Browser time (desktop)". It is *not* summed with phone screen time unless the parent chooses "combined"; default is separate cards to avoid mixed semantics.
5. Sessions are **idempotent** by `(deviceId, clientSessionId)`; interval merging for overlaps is done in the aggregation job, not at ingest.

---

## 5. System Architecture

### 5.1 Why a modular monolith first

- One deployable, one DB transaction boundary, trivial local dev on 8 GB RAM.
- Clear module boundaries (`src/modules/*`) with explicit public interfaces and **no cross-module Prisma access** (modules call each other's exported functions).
- Natural split lines later: **ingestion** (write-heavy, stateless), **sync gateway** (WebSockets/push), **worker** (jobs). They share the codebase but can be run as separate processes from the same image with different entry points (`api`, `worker`) long before true microservices are needed.

### 5.2 High-level architecture

```mermaid
flowchart LR
  subgraph Parent
    PW[Parent Web Dashboard<br/>React]
    PM[Parent Mobile App<br/>Expo RN]
  end
  subgraph Child Devices
    CA[Android Child App<br/>RN UI + Kotlin Engine]
    CI[iOS Child App<br/>RN UI + Swift + Screen Time ext]
    BX[Browser Extension<br/>MV3]
  end
  subgraph Backend [Modular Monolith - Node/Express]
    API[REST API]
    WS[WebSocket Gateway<br/>foreground only]
    POL[Policy Module<br/>+ Compiler + Signer]
    ING[Ingestion Module]
    JOB[Worker: pg-boss jobs]
  end
  DB[(PostgreSQL)]
  FCM[FCM]
  APNS[APNs]
  PW & PM -->|HTTPS REST + JWT| API
  PW & PM -.->|WS live view| WS
  CA & CI & BX -->|HTTPS REST + device token| API
  API --> POL & ING
  POL --> DB
  ING --> DB
  JOB --> DB
  API --> DB
  POL -->|wake-up data msg| FCM --> CA
  POL -->|silent/alert push| APNS --> CI
  JOB -->|parent alerts| FCM & APNS
```

### 5.3 Backend module architecture

```mermaid
flowchart TB
  subgraph modules
    AUTH[auth<br/>users, sessions, device credentials]
    FAM[family<br/>families, members, children]
    DEV[devices<br/>pairing, capabilities, heartbeat]
    POL[policy<br/>CRUD, versioning, validate, compile, sign, ack]
    ACT[activity<br/>ingest batches, queries]
    AGG[analytics<br/>aggregates, reports]
    NOT[notifications<br/>rules, push, email]
    CAT[catalog<br/>app catalog, domain categories]
    AUD[audit<br/>audit log]
  end
  FAM --> AUTH
  DEV --> FAM
  POL --> DEV
  ACT --> DEV
  AGG --> ACT
  NOT --> POL & ACT & DEV
  POL --> CAT
  AUD -.writes from all.-> AUTH & FAM & DEV & POL
```

Rules: each module has `routes.ts`, `handlers.ts`, `schemas.ts` (Zod, re-exported from `packages/validation` when shared), `db.ts` (Prisma queries for *that module's tables only*), `index.ts` (public functions). **Do not add repository/service/DTO layers**; a handler that calls `db.ts` functions is enough until a module has genuinely complex logic (policy compiler and aggregation are the two that will).

### 5.4 Parent mobile architecture
Expo Router (file-based) · TanStack Query (server cache) · Zustand for small UI state · `expo-secure-store` for refresh token · `expo-notifications` for push · `packages/api-client` for typed calls. No native modules. Screens: Auth, Family, Child detail (usage, policy editor), Device health, Notifications, Pairing (shows QR/code).

### 5.5 Android child architecture

```mermaid
flowchart TB
  subgraph RN [React Native UI - may be dead]
    UI[Onboarding / Pairing / Permissions / PIN / Status]
  end
  subgraph Bridge [Expo Module: enforcement-android]
    BR[getStatus, openSettings, pair, setPin, getLocalStats]
  end
  subgraph Native [Kotlin - always authoritative]
    PS[(PolicyStore<br/>Room + signed JSON)]
    EV[EnforcementEngine<br/>pure Kotlin evaluator]
    FG[ForegroundService<br/>foreground-app watcher + tick]
    AS[AccessibilityService<br/>optional]
    VPN[DnsFilterVpnService]
    UC[UsageCollector<br/>UsageEvents -> sessions]
    BL[BlockActivity / overlay]
    SY[SyncManager<br/>OkHttp + WorkManager]
    FM[FcmService<br/>wake-up]
    DA[DeviceAdminReceiver]
    OB[(Outbox<br/>sessions, attempts, heartbeats)]
  end
  UI <--> BR <--> PS
  FM --> SY --> PS
  PS --> EV
  FG --> EV --> BL
  AS --> EV
  VPN --> EV
  UC --> OB
  EV --> OB
  SY --> OB
```

Key rules:
- **Single source of truth on device:** `PolicyStore` holds the last verified compiled policy + its version + `validUntil`.
- **Evaluator is a pure function:** `evaluate(policy, now, usageSnapshot, appId?) → Decision`. All unit-tested on JVM.
- **Outbox pattern:** everything to upload is written to a local table first; `SyncManager` drains it in batches with idempotency keys. No data loss on kill/offline.
- **Tick loop:** a foreground service (with persistent, honest notification — "Parental controls active") runs a lightweight loop (event-driven where possible; coarse timer ~1–2 s only while screen is on, via `ACTION_SCREEN_ON/OFF` broadcasts). Do **not** poll at 2 s while the screen is off (open-source examples that do this ✅ §12 are battery anti-patterns).

### 5.6 iOS child architecture

```mermaid
flowchart TB
  RNI[RN UI] <--> BRI[Expo Module: enforcement-ios]
  BRI --> FC[FamilyControls AuthorizationCenter]
  BRI --> MS[ManagedSettingsStore]
  BRI --> DAC[DeviceActivityCenter schedules]
  AG[(App Group container<br/>shared UserDefaults/files)]
  BRI <--> AG
  MON[DeviceActivityMonitor ext] <--> AG
  SHC[ShieldConfiguration ext] <--> AG
  SHA[ShieldAction ext] <--> AG
  MON --> MS
  MON -.limited network, small budget.-> API[(Backend)]
  REP[DeviceActivityReport ext<br/>display only]
```

Rule: the compiled iOS policy is translated into **(a)** a `ManagedSettingsStore` state, **(b)** a set of pre-registered `DeviceActivitySchedule`s/events covering the next N days, **(c)** an App-Group JSON the extensions read. Extensions never parse large JSON or call heavy libraries.

### 5.7 Browser extension architecture

```mermaid
flowchart LR
  SW[Service worker / event page<br/>stateless, event-driven] --> ST[(chrome.storage.local<br/>policy + outbox)]
  SW --> DNR[declarativeNetRequest<br/>dynamic rules + static rulesets]
  SW --> AL[chrome.alarms<br/>sync + schedule boundaries]
  SW -->|HTTPS| API[(Backend)]
  POP[Popup / options / blocked page] <--> ST
  TR[Tracker: webNavigation + idle + tabs] --> ST
```

### 5.8 Device-to-backend communication (all clients)

| Concern | Mechanism |
|---|---|
| Authentication | Device access token (short-lived JWT, `typ: device`) + rotating device refresh token; optional proof-of-possession later (§10.3) |
| Wake-up | FCM data message (Android), APNs (iOS), alarms/poll (browser) |
| Policy delivery | `GET /devices/:id/policy` with `If-None-Match: "<version>"` → `304` or compiled signed policy |
| Acknowledge | `POST /devices/:id/policy/acknowledge` with applied version + per-capability results |
| Activity upload | `POST /devices/:id/activities/batch` (idempotent) |
| Health | `POST /devices/:id/heartbeat` (or piggy-backed on batch) |

### 5.9 Policy synchronisation (sequence)

```mermaid
sequenceDiagram
  participant P as Parent App
  participant A as API/Policy module
  participant DB as Postgres
  participant F as FCM/APNs
  participant D as Child Device
  P->>A: PATCH /policies/:id (edits)
  A->>A: validate (Zod + semantic rules)
  A->>DB: insert PolicyVersion n+1 (immutable), set Policy.currentVersion
  A->>DB: set Device.desiredVersion for each child device
  A->>F: data message {type:"policy_changed", v:n+1, collapseKey}
  F-->>D: wake (best effort)
  D->>A: GET /devices/:id/policy (If-None-Match: n)
  A->>A: compile for device capabilities + sign (JWS)
  A-->>D: 200 compiled policy v n+1
  D->>D: verify signature, persist, apply, evaluate now
  D->>A: POST acknowledge {version:n+1, results:[...]}
  A->>DB: Device.appliedVersion=n+1, PolicyDelivery row
  A-->>P: (WS/poll) device now "in sync"
  Note over D,A: If FCM is lost, next heartbeat/poll still finds desired>applied
```

### 5.10 Activity collection and processing

```mermaid
flowchart LR
  D[Device outbox] -->|batch POST, idempotent| ING[Ingestion handler<br/>validate, dedupe by batchId]
  ING --> T[(AppUsageSession / WebsiteVisit / BlockedAttempt)]
  ING -->|enqueue| Q[(pg-boss)]
  Q --> AGG[Aggregation job<br/>merge overlaps, upsert UsageDailyAggregate]
  Q --> NOTIF[Rule evaluation<br/>limit reached, tamper, stale]
  AGG --> UDA[(UsageDailyAggregate)]
  RET[Nightly retention job] --> T
```

### 5.11 Separation of concerns (required by spec)

| Concern | Where it lives | Output |
|---|---|---|
| Policy management | `modules/policy` | Immutable `PolicyVersion` (platform-independent) |
| Platform translation | `modules/policy/compilers/{android,ios,browser}.ts` | Compiled, capability-filtered, signed payload |
| Native enforcement | Kotlin / Swift / extension | Real blocking; local decisions |
| Activity collection | Device collectors + `modules/activity` | Typed raw rows |
| Activity processing | `modules/analytics` + worker | `UsageDailyAggregate`, notifications |
| Reporting | REST read endpoints + dashboard | Charts |

### 5.12 `DeviceCapability` model

Reported by the device at registration and on change (via heartbeat); the dashboard uses it to **hide or grey-out unsupported controls** and to explain why.

```ts
export type CapabilityKey =
  | 'APP_USAGE_READ' | 'APP_BLOCK' | 'APP_DAILY_LIMIT' | 'SCREEN_TIME_LIMIT'
  | 'SCHEDULE' | 'WEB_DOMAIN_BLOCK' | 'WEB_CATEGORY_BLOCK' | 'WEB_ALLOWLIST_MODE'
  | 'WEB_HISTORY' | 'APP_INVENTORY' | 'UNINSTALL_PROTECTION' | 'TAMPER_DETECTION'
  | 'REALTIME_WAKE' | 'APP_USAGE_REPORTING';

export type CapabilityState =
  | 'ACTIVE'                 // supported and currently enforceable
  | 'PERMISSION_REQUIRED'    // supported, user/device permission missing
  | 'DEGRADED'               // works with caveats (see reason)
  | 'UNSUPPORTED';           // platform/mode cannot do it

export interface DeviceCapability {
  key: CapabilityKey;
  state: CapabilityState;
  reason?: string;                // 'ACCESSIBILITY_DISABLED' | 'VPN_NOT_ALWAYS_ON' | 'IOS_NO_USAGE_EXPORT' ...
  requiredAction?: string;        // deep-link key the child app can open
  since: string;                  // ISO
}

export interface DeviceDescriptor {
  platform: 'ANDROID' | 'IOS' | 'CHROME' | 'EDGE' | 'FIREFOX';
  enforcementTier: 'STANDARD' | 'DEVICE_OWNER' | 'SCREEN_TIME_CHILD' | 'BROWSER_ONLY';
  osVersion: string;
  appVersion: string;
  manufacturer?: string;
  model?: string;
  capabilities: DeviceCapability[];
}
```

The compiler consumes `DeviceDescriptor` and emits `unsupportedRules[]` in the compiled policy so the parent can see "3 rules not enforceable on Aarav's iPad".

---
## 6. Policy Engine

### 6.1 Principles
1. **One policy per child**, platform-independent. Parents never see "AccessibilityService" or "FamilyActivitySelection".
2. **Immutable versions.** Every edit creates `PolicyVersion n+1`. Devices acknowledge a version number.
3. **Compile, don't interpret on server.** The server compiles intent → per-device rules; devices only evaluate compiled rules.
4. **Local evaluation with last-known-good.** A device never needs the network to decide.
5. **Signed payloads.** Compiled policies are JWS-signed (EdDSA) by a server key; devices pin the public key (with `kid` for rotation).

### 6.2 Time semantics (a common bug source)
- Schedules are stored as **local wall-clock times + IANA timezone** (`Asia/Kolkata`), never UTC offsets, so DST and travel behave.
- `timezone` is the child's *home* timezone in the policy; the device evaluates in that zone regardless of the device's current zone setting (prevents "change timezone to dodge bedtime"). Parent may switch to `followDevice` mode explicitly (e.g., travelling).
- Day boundary for daily limits = local midnight in the policy timezone (configurable `dayResetTime`, default `00:00`).
- Device clock is untrusted: `trustedNow = deviceNow + serverOffset`, where `serverOffset` is refreshed on each sync; on clock change events the offset is re-validated against `elapsedRealtime`.

### 6.3 TypeScript contracts (`packages/policy-contracts`)

```ts
export type Weekday = 'MON'|'TUE'|'WED'|'THU'|'FRI'|'SAT'|'SUN';
export type HHmm = `${number}${number}:${number}${number}`; // validated by Zod regex ^([01]\d|2[0-3]):[0-5]\d$

export interface PolicyDocument {
  schemaVersion: 1;
  childId: string;
  version: number;                 // = PolicyVersion.version
  issuedAt: string;                // ISO 8601
  expiresAt?: string;              // optional hard expiry (see 6.7)
  timezone: string;                // IANA
  timezoneMode: 'fixed' | 'followDevice';
  dayResetTime: HHmm;

  screenTime: {
    dailyLimitMinutes: Partial<Record<Weekday | 'DEFAULT', number>>; // minutes; absent => no limit
    countedCategories: 'ALL_EXCEPT_ALLOWLIST';                       // MVP: single mode
  };

  apps: {
    mode: 'DENYLIST' | 'ALLOWLIST';       // ALLOWLIST = only listed apps usable (plus system essentials)
    rules: AppRule[];
    categoryRules: CategoryRule[];
    alwaysAllowed: AppRef[];              // phone, SMS, maps, emergency: exempt from limits/schedules
  };

  web: {
    mode: 'DENYLIST' | 'ALLOWLIST';
    blockedDomains: DomainRule[];
    allowedDomains: DomainRule[];         // wins over blockedDomains and categories
    blockedCategories: WebCategoryId[];
    safeSearch: boolean;                  // best-effort (DNS-level rewrite, browser-extension where possible)
  };

  schedules: Schedule[];
  exceptions: TemporaryException[];       // time-boxed parent grants
  emergency?: EmergencyState;             // see 6.8
  tamperResponse: {
    onPermissionLoss: 'NOTIFY' | 'NOTIFY_AND_LOCK';  // LOCK only where tier supports it
    onClockChange:    'NOTIFY' | 'NOTIFY_AND_LOCK';
    staleAfterHours: number;                          // device "stale" threshold for parent alert
    failMode: 'KEEP_LAST' | 'RESTRICT_AFTER_DAYS';
    restrictAfterDays?: number;
  };
}

export interface AppRef {
  // Platform-neutral reference. Android: packageName. iOS: not available (tokens) -> see iosSelection.
  catalogId?: string;          // AppCatalog.id (canonical app identity across stores)
  androidPackage?: string;
  iosSelectionToken?: string;  // opaque, device-specific encoding produced by Screen Time picker
  label?: string;              // display only
}

export interface AppRule {
  app: AppRef;
  action: 'BLOCK' | 'LIMIT' | 'ALLOW';
  dailyLimitMinutes?: number;                 // when action = LIMIT
  schedules?: string[];                       // optional Schedule ids this rule is restricted to
}

export interface CategoryRule {
  category: string;                           // from AppCatalog categories, e.g. 'GAMES','SOCIAL','VIDEO'
  action: 'BLOCK' | 'LIMIT';
  dailyLimitMinutes?: number;
}

export interface DomainRule { domain: string; includeSubdomains: boolean; } // eTLD+1-aware, lower-cased, punycode
export type WebCategoryId = 'ADULT'|'GAMBLING'|'MALWARE'|'SOCIAL'|'GAMES'|'STREAMING'|'DRUGS'|'VIOLENCE';

export interface Schedule {
  id: string;
  name: string;                                // 'Bedtime', 'School'
  kind: 'BEDTIME' | 'SCHOOL' | 'CUSTOM';
  days: Weekday[];
  start: HHmm;
  end: HHmm;                                   // end < start => crosses midnight
  effect: 'BLOCK_ALL_EXCEPT_ALLOWED' | 'BLOCK_APPS' | 'BLOCK_WEB' | 'LIMIT_APPS_TO_ALLOWLIST';
  targets?: AppRef[];                          // for BLOCK_APPS
  enabled: boolean;
}

export interface TemporaryException {
  id: string;
  kind: 'EXTEND_DAILY_LIMIT' | 'EXTEND_APP_LIMIT' | 'LIFT_SCHEDULE' | 'UNBLOCK_APP' | 'UNBLOCK_DOMAIN';
  app?: AppRef; domain?: string; scheduleId?: string;
  extraMinutes?: number;                       // for EXTEND_*
  validFrom: string; validUntil: string;       // ISO, must be <= 24h in the future unless parent explicitly sets longer
  grantedBy: string;                           // userId
}

export interface EmergencyState {
  lock: boolean;                               // "pause the internet/phone" now
  until?: string;
  message?: string;
}
```

### 6.4 Example policy JSON

```json
{
  "schemaVersion": 1,
  "childId": "0190f7c2-6e3a-7c11-9d6b-4a2f9f0c1b11",
  "version": 14,
  "issuedAt": "2026-11-19T09:12:00Z",
  "timezone": "Asia/Kolkata",
  "timezoneMode": "fixed",
  "dayResetTime": "00:00",
  "screenTime": {
    "dailyLimitMinutes": { "DEFAULT": 120, "SAT": 180, "SUN": 180 },
    "countedCategories": "ALL_EXCEPT_ALLOWLIST"
  },
  "apps": {
    "mode": "DENYLIST",
    "rules": [
      { "app": { "androidPackage": "com.example.shortvideo", "label": "ShortVideo" }, "action": "BLOCK" },
      { "app": { "androidPackage": "com.example.game", "label": "BigGame" }, "action": "LIMIT", "dailyLimitMinutes": 45 }
    ],
    "categoryRules": [{ "category": "SOCIAL", "action": "LIMIT", "dailyLimitMinutes": 30 }],
    "alwaysAllowed": [
      { "androidPackage": "com.android.dialer" },
      { "androidPackage": "com.google.android.apps.maps" }
    ]
  },
  "web": {
    "mode": "DENYLIST",
    "blockedDomains": [{ "domain": "example-bad.com", "includeSubdomains": true }],
    "allowedDomains": [{ "domain": "khanacademy.org", "includeSubdomains": true }],
    "blockedCategories": ["ADULT", "GAMBLING", "MALWARE"],
    "safeSearch": true
  },
  "schedules": [
    { "id": "sch_bed", "name": "Bedtime", "kind": "BEDTIME",
      "days": ["SUN","MON","TUE","WED","THU"], "start": "21:30", "end": "06:30",
      "effect": "BLOCK_ALL_EXCEPT_ALLOWED", "enabled": true },
    { "id": "sch_school", "name": "School", "kind": "SCHOOL",
      "days": ["MON","TUE","WED","THU","FRI"], "start": "08:00", "end": "14:30",
      "effect": "LIMIT_APPS_TO_ALLOWLIST", "enabled": true }
  ],
  "exceptions": [
    { "id": "ex_01", "kind": "EXTEND_DAILY_LIMIT", "extraMinutes": 30,
      "validFrom": "2026-11-19T12:00:00Z", "validUntil": "2026-11-19T18:29:59Z",
      "grantedBy": "0190f7c2-1111-7000-8000-00000000aaaa" }
  ],
  "tamperResponse": {
    "onPermissionLoss": "NOTIFY", "onClockChange": "NOTIFY",
    "staleAfterHours": 6, "failMode": "KEEP_LAST"
  }
}
```

### 6.5 Validation (two layers)
1. **Structural** — Zod schema in `packages/validation` (types, regexes, bounds: limits 0–1440 min, ≤ 500 app rules, ≤ 5000 domains in MVP, ISO dates, `start != end`).
2. **Semantic** (server only) — e.g. schedule ids unique; `LIMIT` has `dailyLimitMinutes`; exceptions' `validUntil` > `validFrom`; domains normalised (lowercase, IDN→punycode, strip scheme/path, reject IPs/`localhost`/wildcards inside labels); referenced `catalogId`s exist; the **child's own app (our child app) and system essentials can never be blocked** (prevents bricking the phone); total payload < 256 KB.
3. **Capability preview** (non-blocking): compile for each of the child's devices and return `warnings[]` ("iOS devices cannot enforce per-app minute limits on app X — will use category threshold").

### 6.6 Versioning, synchronisation, acknowledgement
- `Policy` (1 per child) points at `currentVersion`. `PolicyVersion(policyId, version)` unique; content is `jsonb`; `createdBy`, `changeNote`.
- Edits use **optimistic concurrency**: client sends `baseVersion`; if `baseVersion != currentVersion` → `409 POLICY_VERSION_CONFLICT` with the latest document, so two guardians don't overwrite each other.
- Device state: `desiredVersion` (set on publish), `appliedVersion` (set on ack), `lastAckAt`.
- **Ack payload** states per capability: `APPLIED | PARTIAL | FAILED | SKIPPED_UNSUPPORTED` with `reasonCode`. Server keeps the last N acks per device (`PolicyDelivery`).
- **Drift detection:** `desiredVersion > appliedVersion` for more than `X` minutes ⇒ device card shows "Not in sync".

### 6.7 Expiration and offline enforcement
- Compiled policy has `validUntil` (default = now + 14 days) and `softRefreshAfter` (default 6 h). The device refreshes on `softRefreshAfter`; if it cannot refresh it **keeps enforcing the last-known policy** (`failMode: KEEP_LAST`). Past `validUntil` behaviour is configured: `KEEP_LAST` (default; parent is alerted "stale") or `RESTRICT_AFTER_DAYS` (device falls back to allowlist-only mode). The default is deliberately lenient — a dead Wi-Fi router should not lock a child out of a phone call.
- `PolicyException`s expire locally by timestamp; they are evaluated against `trustedNow`.

### 6.8 Emergency updates
`POST /children/:id/emergency-lock` creates a high-priority `PolicyVersion` containing `emergency.lock = true` and sends FCM with `priority: high`. Device behaviour: show lock screen with allowlist (phone/emergency numbers only). **Releasing** the lock is another version. If the device is offline the lock applies at next contact — the UI states this honestly ("will apply when the device reconnects").

### 6.9 Conflict-resolution rules (normative, implemented in `EnforcementEngine.evaluate`)

Evaluated top to bottom; first matching **deny** decides, with explicit exceptions:

1. `emergency.lock` → **DENY** everything except system-essential/emergency allowlist. *(Not overridable by exceptions.)*
2. App in `apps.alwaysAllowed` → **ALLOW** (exempt from 3–6; still subject to 1).
3. Active **schedule** whose effect covers the target → **DENY** (unless an active `LIFT_SCHEDULE` exception for that schedule).
4. App rule `BLOCK`, or `mode = ALLOWLIST` and app not listed → **DENY** (unless active `UNBLOCK_APP`).
5. Per-app / per-category limit reached → **DENY** (limit += active `EXTEND_APP_LIMIT` minutes).
6. Total daily screen-time limit reached → **DENY** (limit += active `EXTEND_DAILY_LIMIT` minutes).
7. Otherwise **ALLOW**.

Web: `allowedDomains` > `blockedDomains` > `blockedCategories` > default; schedule `BLOCK_WEB` applies before domain rules. Allow-list **always beats** category block, **never beats** emergency lock or schedule web block.

Multiple limits: **most restrictive wins**. Multiple guardians: last-write-wins *per version*, protected by `baseVersion` check.

```ts
export type Decision =
  | { allow: true }
  | { allow: false; reason: 'EMERGENCY'|'SCHEDULE'|'APP_BLOCKED'|'APP_LIMIT'|'CATEGORY_LIMIT'|'DAILY_LIMIT'|'NOT_ALLOWLISTED';
      ruleId?: string; unblocksAt?: string };

export function evaluateApp(
  policy: CompiledAndroidPolicy, trustedNow: Date, usage: UsageSnapshot, pkg: string
): Decision; // pure, deterministic, unit-tested with table-driven cases (Kotlin port mirrors TS reference tests)
```
**Cross-language parity:** the evaluator exists in Kotlin (device), Swift (iOS extension, simplified) and TypeScript (server preview + reference). Keep a shared **golden test-vector file** (`packages/policy-contracts/test-vectors/*.json`: policy + usage + time + app → expected decision) executed by all three implementations. This is the single most valuable test asset in the project.

### 6.10 Compilation to platform configurations

```mermaid
flowchart LR
  PD[PolicyDocument v14] --> C{Compiler<br/>+ DeviceDescriptor}
  C -->|ANDROID/STANDARD| CA[CompiledAndroidPolicy]
  C -->|ANDROID/DEVICE_OWNER| CAD[CompiledAndroidPolicy + dpm ops]
  C -->|IOS| CI[CompiledIosPolicy]
  C -->|CHROME/EDGE/FIREFOX| CB[CompiledBrowserPolicy]
  C --> UNS[unsupportedRules / warnings]
```

**Android compiled form (excerpt):**
```json
{
  "kind": "android", "policyVersion": 14, "deviceId": "dev_123", "tier": "STANDARD",
  "validUntil": "2026-12-03T09:12:00Z", "softRefreshAfter": "2026-11-19T15:12:00Z",
  "timezone": "Asia/Kolkata", "dayResetTime": "00:00",
  "dailyLimitSeconds": { "DEFAULT": 7200, "SAT": 10800, "SUN": 10800 },
  "appRules": [
    { "pkg": "com.example.shortvideo", "action": "BLOCK" },
    { "pkg": "com.example.game", "action": "LIMIT", "limitSeconds": 2700 }
  ],
  "categoryLimits": [{ "category": "SOCIAL", "limitSeconds": 1800, "packages": ["com.example.chat", "com.example.photos"] }],
  "alwaysAllowed": ["com.android.dialer", "com.google.android.apps.maps"],
  "schedules": [ /* as in document */ ],
  "exceptions": [ /* as in document */ ],
  "dns": { "mode": "DENYLIST", "blocked": ["example-bad.com"], "allowed": ["khanacademy.org"],
           "categoryLists": [{ "id": "ADULT", "url": "/api/v1/catalog/domain-lists/ADULT?v=42", "sha256": "…" }] },
  "unsupportedRules": []
}
```
Domain category lists are **separate versioned downloads** (compressed; the device builds a hash set/bloom filter on disk) so each policy payload stays small.

**iOS compiled form:** list of `{selectionBlob, action}` for shields (blobs only produced from picker), schedules expanded into `DeviceActivitySchedule` descriptors for the next 7 days, thresholds as `DeviceActivityEvent` descriptors; `unsupportedRules` includes "PER_APP_MINUTE_REPORTING".

**Browser compiled form:** DNR rule JSON (`id`, `priority`, `condition.requestDomains`, `action`) generated server-side; *static* big category rulesets shipped in extension updates or fetched and installed as dynamic rules within quota.

---

## 7. Database Design

### 7.1 Principles
- PostgreSQL, UUIDv7 primary keys (time-ordered → good index locality; Prisma supports `@default(uuid(7))` 🟡 version ≥ 5.18).
- Every tenant-owned table carries `familyId` (denormalised where useful) so authorisation checks and **row-level data isolation** are cheap: *every query includes `familyId`*. Optional hardening: Postgres RLS later.
- Timestamps `timestamptz`. Durations in **seconds**, integers.
- Typed activity tables; no generic event blob in MVP (see §0.3 #9).

### 7.2 Entity overview and rationale

| Entity | Purpose | Key fields | Relationships | Indexes | Retention |
|---|---|---|---|---|---|
| User | Guardian account | email (unique, citext), passwordHash, emailVerifiedAt, locale | → FamilyMember, Session | unique(email) | Until account deletion |
| Session (refresh) | Rotating parent refresh tokens | tokenHash, familyTokenId, rotatedAt, revokedAt, expiresAt, userAgent | → User | (userId), unique(tokenHash) | Purge expired > 30 d |
| Family | Tenant | name, timezone, createdBy | → members, children, devices | – | Until deletion |
| FamilyMember | Role membership | familyId, userId, role | unique(familyId,userId) | (userId) | With family |
| ChildProfile | Supervised person | familyId, name, birthYear, avatar | → Policy, Devices | (familyId) | With family; purge on deletion |
| Device | Paired endpoint | familyId, childId, platform, tier, name, osVersion, appVersion, status, lastSeenAt, desiredPolicyVersion, appliedPolicyVersion, pushToken, revokedAt | → child, capabilities | (childId), (familyId,status), (lastSeenAt) | Soft-revoke; hard delete after 90 d |
| DeviceCapability | Capability states | deviceId, key, state, reason, updatedAt | unique(deviceId,key) | – | With device |
| DevicePairing | One-time pairing | familyId, childId, codeHash, qrNonceHash, expiresAt, consumedAt, attempts, createdBy | → child | (expiresAt), unique(codeHash) | Purge 7 d after expiry |
| DeviceSession | Rotating device credentials | deviceId, tokenHash, rotatedAt, revokedAt, publicKey? | → Device | unique(tokenHash) | Purge expired |
| Policy | Policy head per child | childId (unique), currentVersion | → versions | unique(childId) | With child |
| PolicyVersion | Immutable snapshots | policyId, version, document (jsonb), createdBy, changeNote | unique(policyId,version) | – | Keep last 50 per policy + all within 1 y |
| PolicyException | Temporary grants (also embedded into versions) | childId, kind, payload, validFrom, validUntil, grantedBy | → child | (childId, validUntil) | 90 d |
| PolicyDelivery | Ack log | deviceId, version, status, results (jsonb), receivedAt | → device | (deviceId, receivedAt desc) | Keep last 30/device |
| IngestBatch | Idempotency + audit of uploads | deviceId, batchId, receivedAt, counts | unique(deviceId,batchId) | (receivedAt) | 30 d |
| AppUsageSession | Closed foreground interval | deviceId, childId, familyId, appRef (pkg), startedAt, endedAt, durationSec, clientSessionId | → device | unique(deviceId,clientSessionId); (childId,startedAt); (deviceId,startedAt) | **Raw: 90 d** (configurable), aggregates longer |
| WebsiteVisit | Domain-level visit (no full URL by default) | deviceId, childId, domain, visitedAt, activeSec?, source (DNS/EXTENSION), blocked bool | → device | (childId,visitedAt); (childId,domain) | **Raw: 30 d** |
| BlockedAttempt | Block events | deviceId, childId, kind (APP/DOMAIN/SCHEDULE/LIMIT), subject, reason, occurredAt, clientEventId | → device | (childId,occurredAt); unique(deviceId,clientEventId) | 90 d |
| DeviceHeartbeat | Health pings | deviceId, at, batteryPct?, permissions (jsonb), netType, appVersion | → device | (deviceId, at desc) | **7 d raw**; keep `Device.lastSeenAt` |
| UsageDailyAggregate | Report source | childId, deviceId, localDate, kind (TOTAL/APP/CATEGORY/DOMAIN), subjectKey, seconds, sessionCount | unique(deviceId,localDate,kind,subjectKey) | (childId,localDate) | **Keep 2 y** |
| AppCatalog | Canonical app identity + category | id, androidPackage?, iosBundleId?, name, category, source | unique(androidPackage) | (category) | Global |
| InstalledApp | Per-device inventory | deviceId, androidPackage, label, versionName, firstSeenAt, removedAt | unique(deviceId,androidPackage) | – | With device |
| WebsiteCategory | Category definitions + list versions | id, name, listVersion, listSha256, sourceLicense | – | – | Global |
| DomainCategory | domain→category (optional server-side lookup for reports) | domain, categoryId, listVersion | unique(domain,categoryId) | (domain) | Global; rebuilt on list updates |
| Notification | Parent-facing notifications | familyId, userId?, childId?, kind, payload, readAt, dedupeKey | – | (userId,readAt), unique(dedupeKey) | 60 d |
| PushToken | Parent push tokens | userId, platform, token, lastSeenAt | unique(token) | – | Purge stale |
| AuditLog | Security & admin events | familyId, actorUserId?, actorDeviceId?, action, entity, entityId, ip, uaHash, meta (jsonb), at | – | (familyId, at desc) | **1 y** (security) |

**Dropped/merged vs the requested list:** `ActivityEvent` (replaced by typed tables + `IngestBatch`). Everything else is kept.

### 7.3 Entity-relationship diagram

```mermaid
erDiagram
  User ||--o{ FamilyMember : has
  Family ||--o{ FamilyMember : has
  Family ||--o{ ChildProfile : has
  Family ||--o{ Device : owns
  ChildProfile ||--o{ Device : uses
  ChildProfile ||--|| Policy : governed_by
  Policy ||--o{ PolicyVersion : versions
  Device ||--o{ DeviceCapability : reports
  Device ||--o{ DeviceSession : authenticates
  Device ||--o{ PolicyDelivery : acks
  Device ||--o{ InstalledApp : inventory
  Device ||--o{ AppUsageSession : records
  Device ||--o{ WebsiteVisit : records
  Device ||--o{ BlockedAttempt : records
  Device ||--o{ DeviceHeartbeat : pings
  Device ||--o{ IngestBatch : uploads
  ChildProfile ||--o{ UsageDailyAggregate : summarised
  ChildProfile ||--o{ PolicyException : granted
  ChildProfile ||--o{ DevicePairing : pairs
  Family ||--o{ Notification : receives
  Family ||--o{ AuditLog : logs
  User ||--o{ Session : has
  User ||--o{ PushToken : has
  AppCatalog ||--o{ AppUsageSession : classifies
  WebsiteCategory ||--o{ DomainCategory : contains
```

### 7.4 Prisma schema proposal (core; trim as you go)

```prisma
generator client { provider = "prisma-client-js" }   // 🟡 use the generator/config syntax of your installed Prisma major
datasource db { provider = "postgresql" url = env("DATABASE_URL") }

enum FamilyRole { OWNER GUARDIAN VIEWER }
enum Platform { ANDROID IOS CHROME EDGE FIREFOX }
enum EnforcementTier { STANDARD DEVICE_OWNER SCREEN_TIME_CHILD BROWSER_ONLY }
enum DeviceStatus { PENDING ACTIVE REVOKED }
enum CapabilityState { ACTIVE PERMISSION_REQUIRED DEGRADED UNSUPPORTED }
enum AttemptKind { APP DOMAIN SCHEDULE LIMIT }
enum AggKind { TOTAL APP CATEGORY DOMAIN }
enum UsageSource { DEVICE_APP BROWSER_EXTENSION DNS }
enum DeliveryStatus { APPLIED PARTIAL FAILED }

model User {
  id String @id @default(uuid(7)) @db.Uuid
  email String @unique @db.Citext          // enable citext extension in first migration
  passwordHash String
  emailVerifiedAt DateTime?
  locale String @default("en")
  createdAt DateTime @default(now())
  members FamilyMember[]
  sessions Session[]
  pushTokens PushToken[]
}

model Session {
  id String @id @default(uuid(7)) @db.Uuid
  userId String @db.Uuid
  tokenHash String @unique
  tokenFamily String @db.Uuid               // for reuse detection: revoke whole family on reuse
  rotatedAt DateTime?
  revokedAt DateTime?
  expiresAt DateTime
  userAgent String?
  createdAt DateTime @default(now())
  user User @relation(fields: [userId], references: [id], onDelete: Cascade)
  @@index([userId])
  @@index([expiresAt])
}

model Family {
  id String @id @default(uuid(7)) @db.Uuid
  name String
  timezone String @default("UTC")
  createdAt DateTime @default(now())
  members FamilyMember[]
  children ChildProfile[]
  devices Device[]
  notifications Notification[]
  auditLogs AuditLog[]
}

model FamilyMember {
  id String @id @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  userId String @db.Uuid
  role FamilyRole
  createdAt DateTime @default(now())
  family Family @relation(fields: [familyId], references: [id], onDelete: Cascade)
  user User @relation(fields: [userId], references: [id], onDelete: Cascade)
  @@unique([familyId, userId])
  @@index([userId])
}

model ChildProfile {
  id String @id @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  name String
  birthYear Int?
  avatarColor String?
  createdAt DateTime @default(now())
  family Family @relation(fields: [familyId], references: [id], onDelete: Cascade)
  devices Device[]
  policy Policy?
  aggregates UsageDailyAggregate[]
  pairings DevicePairing[]
  @@index([familyId])
}

model Device {
  id String @id @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  childId String @db.Uuid
  platform Platform
  tier EnforcementTier
  name String
  osVersion String?
  appVersion String?
  manufacturer String?
  model String?
  status DeviceStatus @default(ACTIVE)
  lastSeenAt DateTime?
  desiredPolicyVersion Int @default(0)
  appliedPolicyVersion Int @default(0)
  lastAckAt DateTime?
  pushToken String?
  timeOffsetMs Int?                          // last measured device clock offset
  revokedAt DateTime?
  createdAt DateTime @default(now())
  family Family @relation(fields: [familyId], references: [id], onDelete: Cascade)
  child ChildProfile @relation(fields: [childId], references: [id], onDelete: Cascade)
  capabilities DeviceCapability[]
  sessions DeviceSession[]
  deliveries PolicyDelivery[]
  installedApps InstalledApp[]
  @@index([childId])
  @@index([familyId, status])
  @@index([lastSeenAt])
}

model DeviceCapability {
  id String @id @default(uuid(7)) @db.Uuid
  deviceId String @db.Uuid
  key String
  state CapabilityState
  reason String?
  updatedAt DateTime @default(now()) @updatedAt
  device Device @relation(fields: [deviceId], references: [id], onDelete: Cascade)
  @@unique([deviceId, key])
}

model DevicePairing {
  id String @id @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  childId String @db.Uuid
  codeHash String @unique                   // hash of the human-typable code
  expiresAt DateTime
  consumedAt DateTime?
  attempts Int @default(0)
  createdBy String @db.Uuid
  createdAt DateTime @default(now())
  child ChildProfile @relation(fields: [childId], references: [id], onDelete: Cascade)
  @@index([expiresAt])
}

model DeviceSession {
  id String @id @default(uuid(7)) @db.Uuid
  deviceId String @db.Uuid
  tokenHash String @unique
  tokenFamily String @db.Uuid
  publicKey String?                          // optional: device-bound key (§10.3)
  rotatedAt DateTime?
  revokedAt DateTime?
  expiresAt DateTime
  createdAt DateTime @default(now())
  device Device @relation(fields: [deviceId], references: [id], onDelete: Cascade)
  @@index([deviceId])
}

model Policy {
  id String @id @default(uuid(7)) @db.Uuid
  childId String @unique @db.Uuid
  currentVersion Int @default(0)
  updatedAt DateTime @updatedAt
  child ChildProfile @relation(fields: [childId], references: [id], onDelete: Cascade)
  versions PolicyVersion[]
}

model PolicyVersion {
  id String @id @default(uuid(7)) @db.Uuid
  policyId String @db.Uuid
  version Int
  document Json
  createdBy String @db.Uuid
  changeNote String?
  createdAt DateTime @default(now())
  policy Policy @relation(fields: [policyId], references: [id], onDelete: Cascade)
  @@unique([policyId, version])
}

model PolicyDelivery {
  id String @id @default(uuid(7)) @db.Uuid
  deviceId String @db.Uuid
  version Int
  status DeliveryStatus
  results Json?
  receivedAt DateTime @default(now())
  device Device @relation(fields: [deviceId], references: [id], onDelete: Cascade)
  @@index([deviceId, receivedAt(sort: Desc)])
}

model IngestBatch {
  id String @id @default(uuid(7)) @db.Uuid
  deviceId String @db.Uuid
  batchId String                             // client-generated UUID
  receivedAt DateTime @default(now())
  sessions Int @default(0)
  visits Int @default(0)
  attempts Int @default(0)
  @@unique([deviceId, batchId])
  @@index([receivedAt])
}

// NOTE: for partitioned tables the PK must include the partition key (startedAt).
model AppUsageSession {
  id String @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  childId String @db.Uuid
  deviceId String @db.Uuid
  appKey String                              // android package / bundle id / 'browser'
  clientSessionId String
  startedAt DateTime
  endedAt DateTime
  durationSec Int
  source UsageSource @default(DEVICE_APP)
  @@id([id, startedAt])
  @@unique([deviceId, clientSessionId, startedAt])
  @@index([childId, startedAt])
  @@index([deviceId, startedAt])
}

model WebsiteVisit {
  id String @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  childId String @db.Uuid
  deviceId String @db.Uuid
  domain String
  visitedAt DateTime
  activeSec Int?
  source UsageSource
  blocked Boolean @default(false)
  clientEventId String
  @@id([id, visitedAt])
  @@unique([deviceId, clientEventId, visitedAt])
  @@index([childId, visitedAt])
  @@index([childId, domain])
}

model BlockedAttempt {
  id String @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  childId String @db.Uuid
  deviceId String @db.Uuid
  kind AttemptKind
  subject String
  reason String
  occurredAt DateTime
  clientEventId String
  @@id([id, occurredAt])
  @@unique([deviceId, clientEventId, occurredAt])
  @@index([childId, occurredAt])
}

model DeviceHeartbeat {
  id String @default(uuid(7)) @db.Uuid
  deviceId String @db.Uuid
  at DateTime
  batteryPct Int?
  net String?
  permissions Json?
  appVersion String?
  @@id([id, at])
  @@index([deviceId, at(sort: Desc)])
}

model UsageDailyAggregate {
  id String @id @default(uuid(7)) @db.Uuid
  childId String @db.Uuid
  deviceId String @db.Uuid
  localDate DateTime @db.Date
  kind AggKind
  subjectKey String @default("")             // '' for TOTAL; pkg / category / domain otherwise
  source UsageSource @default(DEVICE_APP)
  seconds Int
  sessionCount Int @default(0)
  updatedAt DateTime @updatedAt
  child ChildProfile @relation(fields: [childId], references: [id], onDelete: Cascade)
  @@unique([deviceId, localDate, kind, subjectKey, source])
  @@index([childId, localDate])
}

model AppCatalog {
  id String @id @default(uuid(7)) @db.Uuid
  androidPackage String? @unique
  iosBundleId String? @unique
  name String
  category String
  source String @default("seed")
  updatedAt DateTime @updatedAt
  @@index([category])
}

model InstalledApp {
  id String @id @default(uuid(7)) @db.Uuid
  deviceId String @db.Uuid
  androidPackage String
  label String
  versionName String?
  firstSeenAt DateTime @default(now())
  removedAt DateTime?
  device Device @relation(fields: [deviceId], references: [id], onDelete: Cascade)
  @@unique([deviceId, androidPackage])
}

model WebsiteCategory {
  id String @id                              // 'ADULT', 'GAMBLING', ...
  name String
  listVersion Int @default(0)
  listSha256 String?
  sourceLicense String?                      // record attribution/licence of the upstream list
}

model DomainCategory {
  domain String
  categoryId String
  listVersion Int
  @@id([domain, categoryId])
  @@index([domain])
}

model Notification {
  id String @id @default(uuid(7)) @db.Uuid
  familyId String @db.Uuid
  userId String? @db.Uuid
  childId String? @db.Uuid
  kind String
  payload Json
  dedupeKey String? @unique
  readAt DateTime?
  createdAt DateTime @default(now())
  family Family @relation(fields: [familyId], references: [id], onDelete: Cascade)
  @@index([userId, readAt])
}

model PushToken {
  id String @id @default(uuid(7)) @db.Uuid
  userId String @db.Uuid
  platform String
  token String @unique
  lastSeenAt DateTime @default(now())
  user User @relation(fields: [userId], references: [id], onDelete: Cascade)
}

model AuditLog {
  id String @id @default(uuid(7)) @db.Uuid
  familyId String? @db.Uuid
  actorUserId String? @db.Uuid
  actorDeviceId String? @db.Uuid
  action String
  entity String?
  entityId String?
  ip String?
  uaHash String?
  meta Json?
  at DateTime @default(now())
  family Family? @relation(fields: [familyId], references: [id], onDelete: SetNull)
  @@index([familyId, at(sort: Desc)])
}
```

*Not modelled above for brevity (add when needed):* `PolicyException` (can start embedded inside the policy document), `Family`-level settings. Add `@@index` on JSON only when queries prove necessary.

### 7.5 Important indexes and query patterns
- "Today's usage for child" → `UsageDailyAggregate (childId, localDate)` — **never** scan raw sessions for dashboards.
- "Recent blocked attempts" → `(childId, occurredAt desc)`.
- Device list with health → `Device (familyId, status)` + `lastSeenAt`.
- Ingest dedupe → unique constraints above + `IngestBatch`.
- Add `pg_stat_statements` locally and review the slowest 10 queries monthly.

### 7.6 Partitioning strategy for large tables
- **Not at MVP.** Plain tables are fine until roughly tens of millions of rows per table. Do the shape work now (partition-key-inclusive PKs/uniques, `startedAt` in time-based indexes) so partitioning later is a migration, not a redesign.
- When needed: **declarative range partitioning by month** on `startedAt`/`visitedAt`/`occurredAt`/`at` for `AppUsageSession`, `WebsiteVisit`, `BlockedAttempt`, `DeviceHeartbeat`. Prisma has no partition DSL → create parent tables and partition-management with **raw SQL migrations**; keep the Prisma model matching the parent table. Create partitions ahead (job creates next 2 months). **Retention = `DROP TABLE` old partition** (instant, no vacuum bloat) instead of `DELETE`.
- Unique constraints on partitioned tables **must include the partition key** (reason for the composite uniques above). Clients must send stable `startedAt` for the same event so retries hit the same constraint.

### 7.7 Daily aggregation strategy
1. **On ingest (cheap, near-real-time):** after inserting sessions, enqueue `aggregate(childId, deviceId, localDate)` jobs (debounced by singleton key, e.g. every 60 s).
2. **Aggregation job:** loads that day's sessions, **merges overlapping intervals per app** (OS events occasionally overlap/duplicate), splits sessions crossing local midnight, computes `TOTAL`, per-`APP`, per-`CATEGORY` (via `AppCatalog`), per-`DOMAIN` (from visits) and `UPSERT`s into `UsageDailyAggregate` (idempotent full recompute for the day — simpler and safer than incremental `+=`).
3. **Nightly reconcile:** recompute "yesterday" and "today−2" to absorb late-arriving batches (offline devices). Late data beyond 7 days is accepted but only recomputed on demand.
4. **Limit alerts** are generated by the **device** (authoritative, immediate) and also by the server rule evaluation as a backup.
5. Local dates use the **policy/child timezone**, stored in the aggregate row's `localDate`.

### 7.8 Retention defaults (all configurable constants)
Raw sessions 90 d · raw website visits 30 d · blocked attempts 90 d · heartbeats 7 d · aggregates 2 y · audit 1 y · notifications 60 d · expired pairings/sessions 7–30 d. Document these in the privacy notice shown to parents and children.

### 7.9 Deletion approach
- **Child deletion / device deletion:** hard-delete activity rows (batched deletes by `childId`/`deviceId` via job), aggregates, then entity.
- **Family/account deletion:** soft-mark `deletionRequestedAt` (7-day cancel window), then a job purges everything and writes a minimal **non-personal** audit record.
- **Backups:** deleted data persists in encrypted backups until they age out (document: ≤ 35 days); never restore a backup without re-running the deletion ledger (`DeletionLedger(entityType, entityId, deletedAt)`).

---
## 8. API Architecture

### 8.1 Conventions

| Topic | Decision |
|---|---|
| Base path / versioning | `/api/v1/...`; breaking changes → `/api/v2`. Additive changes are not breaking. Devices send `X-Client-Version`; server may answer `426 UPGRADE_REQUIRED` with `minSupportedVersion` for outdated child apps. |
| Format | JSON, UTF-8, `camelCase`. Times ISO 8601 UTC with `Z`. IDs UUID strings. |
| Auth schemes | `Authorization: Bearer <parentAccessJWT>` (claims: `sub`, `typ:"user"`, `exp` 15 min) · `Authorization: Bearer <deviceAccessJWT>` (`sub`=deviceId, `typ:"device"`, `fam`, `chd`, `exp` 60 min). Parent tokens can never call device-only endpoints and vice versa. |
| AuthZ | Middleware loads membership: `requireFamilyRole(familyId, ['OWNER','GUARDIAN'])`. Every resource id in a path is **resolved to its `familyId` in SQL and compared to the caller's** (never trust ids from body). Device tokens are valid only for `/devices/:ownDeviceId/*`. |
| Pagination | **Cursor-based**: `?limit=50&cursor=<opaque>`; response `{ data: [...], page: { nextCursor, hasMore } }`. Max `limit` 200. |
| Filtering/sorting | Explicit allow-listed params: `from`, `to` (ISO), `deviceId`, `kind`; `sort=-startedAt`. Unknown params → `400`. |
| Rate limiting | Per-IP and per-identity token buckets (`express-rate-limit` + Postgres/memory store at MVP; Redis later). Suggested: auth endpoints 10/min/IP; pairing code redeem 5/min/IP **and** 5 attempts/code; device batch upload 6/min/device; parent API 120/min/user. Responses carry `RateLimit-*` headers and `429` + `Retry-After`. |
| Idempotency | Writes from devices use client-generated `batchId`/`clientEventId`; parent mutating `POST`s accept `Idempotency-Key` (stored 24 h). Replays return the original response. |
| Error format | `application/problem+json`-style: |

```json
{
  "error": {
    "code": "POLICY_VERSION_CONFLICT",
    "message": "Policy was modified by another guardian.",
    "status": 409,
    "requestId": "req_01J...",
    "details": [{ "path": "baseVersion", "issue": "expected 14, got 12" }]
  }
}
```

Standard codes: `VALIDATION_ERROR 400`, `UNAUTHENTICATED 401`, `TOKEN_EXPIRED 401`, `FORBIDDEN 403`, `NOT_FOUND 404`, `CONFLICT 409`, `POLICY_VERSION_CONFLICT 409`, `PAIRING_CODE_INVALID 400`, `PAIRING_CODE_EXPIRED 410`, `DEVICE_REVOKED 401` (device must wipe), `PAYLOAD_TOO_LARGE 413`, `UPGRADE_REQUIRED 426`, `RATE_LIMITED 429`, `INTERNAL 500`. **404 vs 403:** return `404` for resources in other families (don't leak existence).

### 8.2 Endpoint catalogue

Legend — **Auth:** `U` parent JWT · `D` device JWT · `—` none. **Roles:** `O` OWNER, `G` GUARDIAN, `V` VIEWER.

#### 8.2.1 Authentication

| Method | URL | Purpose | Auth / AuthZ | Request | Response | Validation | Errors |
|---|---|---|---|---|---|---|---|
| POST | `/auth/register` | Create user (+ optionally first family) | — | `{email, password, familyName?, timezone?}` | `201 {user, accessToken, refreshToken}` | email RFC-valid ≤254; password ≥ 10 chars, ≤128, not in top-breached list (k-anonymity HIBP optional) | 400, 409 `EMAIL_TAKEN` (use generic message + timing equalisation), 429 |
| POST | `/auth/login` | Password login | — | `{email, password}` | `200 {accessToken, refreshToken, user}` | as above | 401 `INVALID_CREDENTIALS`, 429 (+ progressive delay) |
| POST | `/auth/refresh` | Rotate refresh token | — (refresh token in body) | `{refreshToken}` | `200 {accessToken, refreshToken}` | token exists, unexpired | 401 `TOKEN_REUSED` (revokes family) |
| POST | `/auth/logout` | Revoke current refresh family | U | `{refreshToken}` | `204` | – | 401 |
| POST | `/auth/password/forgot` | Send reset mail | — | `{email}` | `202` always | – | 429 |
| POST | `/auth/password/reset` | Complete reset | — | `{token, newPassword}` | `204` (revokes all sessions) | token single-use, 30 min | 400, 410 |
| POST | `/auth/email/verify` | Verify email | — | `{token}` | `204` | – | 400, 410 |

Web dashboard note: store the refresh token in an **HttpOnly, Secure, SameSite=Strict cookie** (plus CSRF token for `/auth/refresh`) rather than localStorage; mobile uses `expo-secure-store`. Support both by letting the endpoint accept either the cookie or the body field.

#### 8.2.2 Family and children

| Method | URL | Purpose | Auth / AuthZ | Request | Response | Validation | Errors |
|---|---|---|---|---|---|---|---|
| POST | `/families` | Create family | U | `{name, timezone}` | `201 {family}` | name 1–80; IANA tz | 400 |
| GET | `/families/:familyId` | Family + members + children summary | U / any member | – | `200 {family, members[], children[]}` | uuid | 404 |
| POST | `/families/:familyId/members/invitations` | Invite guardian | U / O | `{email, role}` | `201 {invitationId}` (+ email) | role ∈ {G,V} | 403, 409 |
| POST | `/families/invitations/:token/accept` | Accept invite | U | – | `204` | token valid | 410 |
| DELETE | `/families/:familyId/members/:userId` | Remove member | U / O | – | `204` | cannot remove last OWNER | 403, 409 |
| GET | `/families/:familyId/children` | List children | U / member | `?limit&cursor` | `200 {data[]}` | – | 404 |
| POST | `/families/:familyId/children` | Add child | U / O,G | `{name, birthYear?, avatarColor?}` | `201 {child}` (creates empty default Policy v1 from age template) | name 1–50; birthYear 2000–current | 400 |
| PATCH | `/children/:childId` | Update child | U / O,G | partial | `200 {child}` | – | 404 |
| DELETE | `/children/:childId` | Delete child + data | U / O | – | `202 {jobId}` | confirm header `X-Confirm: <childName>` | 403 |

#### 8.2.3 Devices and pairing

| Method | URL | Purpose | Auth / AuthZ | Request | Response | Validation | Errors |
|---|---|---|---|---|---|---|---|
| POST | `/children/:childId/pairings` | Create pairing code + QR payload | U / O,G | `{platformHint?}` | `201 {pairingId, code:"K7QX-93MD", qrPayload, expiresAt}` | code returned **once**; 10-min TTL | 404 |
| POST | `/devices/pair` | Child device redeems code | — (rate-limited) | `{code, device: DeviceDescriptor, pushToken?, publicKey?}` | `201 {deviceId, accessToken, refreshToken, serverTime, signingKeys:[{kid,alg,publicKey}], initialPolicy}` | code format; descriptor validated; `appVersion >= min` | 400 `PAIRING_CODE_INVALID`, 410 `PAIRING_CODE_EXPIRED`, 429 |
| GET | `/devices` | List devices (family-scoped via `?familyId` or child) | U / member | `?familyId&childId&status` | `200 {data[]}` incl. status/online/capabilities summary | – | 403 |
| GET | `/devices/:deviceId` | Device detail + capabilities + sync state | U / member | – | `200 {device, capabilities[], sync:{desired,applied,lastAckAt}, health}` | – | 404 |
| PATCH | `/devices/:deviceId` | Rename/reassign child | U / O,G | `{name?, childId?}` | `200` | child in same family | 404 |
| POST | `/devices/:deviceId/revoke` | Revoke device | U / O,G | `{reason?}` | `200 {status:"REVOKED"}` | – | 404 |
| POST | `/devices/auth/refresh` | Rotate device token | — (refresh in body) | `{refreshToken}` | `200 {accessToken, refreshToken}` | – | 401 `DEVICE_REVOKED`/`TOKEN_REUSED` |
| PUT | `/devices/:deviceId/capabilities` | Report capability change | D | `{capabilities: DeviceCapability[]}` | `204` | keys in enum | 401 |
| PUT | `/devices/:deviceId/push-token` | Update FCM/APNs token | D | `{token, platform}` | `204` | – | – |
| POST | `/devices/:deviceId/heartbeat` | Health ping | D | `{at, batteryPct?, net?, permissions, appVersion, deviceTime}` | `200 {serverTime, desiredPolicyVersion, minSupportedVersion}` | clock skew recorded | 401 |
| PUT | `/devices/:deviceId/inventory` | Upload installed-app list (diff-friendly) | D | `{apps:[{pkg,label,versionName}], full: boolean}` | `204` | ≤ 2000 apps | 413 |

#### 8.2.4 Policies

| Method | URL | Purpose | Auth / AuthZ | Request | Response | Validation | Errors |
|---|---|---|---|---|---|---|---|
| GET | `/children/:childId/policy` | Current policy document (editor source) | U / member | – | `200 {version, document, warnings[]}` | – | 404 |
| PUT | `/children/:childId/policy` | Publish edit (creates new version) | U / O,G | `{baseVersion, document, changeNote?}` | `200 {version, warnings[], devicesNotified}` | Zod + semantic (§6.5) | 400, 409 `POLICY_VERSION_CONFLICT` |
| GET | `/children/:childId/policy/versions` | History | U / member | `?limit&cursor` | `200 {data:[{version,createdBy,changeNote,createdAt}]}` | – | – |
| GET | `/children/:childId/policy/versions/:version` | Specific version | U / member | – | `200` | – | 404 |
| POST | `/children/:childId/exceptions` | Grant temporary exception ("+30 min") | U / O,G | `{kind, extraMinutes?, app?, domain?, validUntil}` | `201 {exception, version}` (creates new version) | ≤ 24 h unless `longGrant:true` | 400 |
| POST | `/children/:childId/emergency-lock` | Lock / unlock now | U / O,G | `{lock: boolean, until?, message?}` | `200 {version, devicesNotified}` | – | – |
| GET | `/devices/:deviceId/policy` | **Device fetch of compiled+signed policy** | D | header `If-None-Match: "14"` | `200 {compiled, jws}` or `304` | – | 401 |
| POST | `/devices/:deviceId/policy/acknowledge` | Device ack | D | `{version, status, results:[{capability, status, reasonCode?}], appliedAt}` | `204` | version ≤ desired | 409 if version unknown |

(`POST /policies` and `PATCH /policies/:id` from your example list are folded into `PUT /children/:childId/policy`, because there is exactly one policy per child; fewer endpoints, same capability.)

#### 8.2.5 Activities, usage, reports

| Method | URL | Purpose | Auth / AuthZ | Request | Response | Validation | Errors |
|---|---|---|---|---|---|---|---|
| POST | `/devices/:deviceId/activities/batch` | Idempotent upload | D | see 8.3 | `200 {batchId, accepted, duplicates, rejected[]}` | ≤ 500 items & ≤ 512 KB gzip; per-item bounds (duration 1 s–24 h, `endedAt ≥ startedAt`, timestamps not > 5 min in future / not > 30 d old) | 400, 413, 429 |
| GET | `/children/:childId/usage` | Aggregates | U / member | `?from&to&groupBy=day\|hour\|app\|category&deviceId` | `200 {series:[…], totals}` | range ≤ 400 d | 400 |
| GET | `/children/:childId/activities` | Raw-ish feed (sessions/visits) | U / member | `?kind&from&to&limit&cursor` | `200 {data, page}` | kind allow-list | – |
| GET | `/children/:childId/blocked-attempts` | Blocked attempts | U / member | `?from&to&limit&cursor&kind` | `200` | – | – |
| GET | `/families/:familyId/overview` | Dashboard overview | U / member | `?date` | `200 {children:[{today, limit, devices, alerts}]}` | – | – |
| GET | `/children/:childId/apps` | Union of installed apps across devices + catalogue category | U / member | – | `200 {apps[]}` | – | – |

#### 8.2.6 Catalogue, notifications, misc

| Method | URL | Purpose | Auth | Notes |
|---|---|---|---|---|
| GET | `/catalog/domain-lists/:categoryId` | Versioned compressed category list (`ETag`, `Content-Encoding: gzip`) | D | Long cache; list version in policy. |
| GET | `/notifications` | List | U | cursor-paged. |
| POST | `/notifications/:id/read` | Mark read | U | – |
| PUT | `/me/push-token` | Register parent push token | U | – |
| GET | `/health` / `/ready` | Liveness / readiness (DB ping) | — | For hosting. |
| GET | `/me` | Current user + memberships | U | – |

### 8.3 Sample payloads

**Pair a device — request**
```json
POST /api/v1/devices/pair
{
  "code": "K7QX-93MD",
  "device": {
    "platform": "ANDROID", "enforcementTier": "STANDARD",
    "osVersion": "14", "appVersion": "0.3.1", "manufacturer": "Xiaomi", "model": "Redmi Note 12",
    "capabilities": [
      { "key": "APP_USAGE_READ", "state": "PERMISSION_REQUIRED", "reason": "USAGE_ACCESS_MISSING", "since": "2026-11-19T09:00:00Z" },
      { "key": "WEB_DOMAIN_BLOCK", "state": "PERMISSION_REQUIRED", "reason": "VPN_NOT_GRANTED", "since": "2026-11-19T09:00:00Z" }
    ]
  },
  "pushToken": "fcm:eXaMpLe…",
  "publicKey": "base64-ed25519-or-ecdsa-spki"
}
```
**Response**
```json
201
{
  "deviceId": "0190f7c3-aaaa-7001-9111-0a0b0c0d0e0f",
  "accessToken": "<jwt typ=device>", "refreshToken": "<opaque 256-bit>",
  "serverTime": "2026-11-19T09:02:11Z",
  "signingKeys": [{ "kid": "pol-2026-01", "alg": "EdDSA", "publicKey": "MCowBQYDK2VwAyEA…" }],
  "initialPolicy": { "compiled": { "…": "…" }, "jws": "<compact JWS>" }
}
```

**Batch upload — request**
```json
POST /api/v1/devices/0190…0e0f/activities/batch
Idempotency-Key: 8d3c2b0e-…   (same value as batchId)
Content-Encoding: gzip
{
  "batchId": "8d3c2b0e-4c8e-4f0e-8d19-7a6bde3b0b21",
  "deviceTime": "2026-11-19T10:00:00Z",
  "sessions": [
    { "clientSessionId": "s-1731990000-01", "appKey": "com.example.game",
      "startedAt": "2026-11-19T09:10:00Z", "endedAt": "2026-11-19T09:34:10Z", "durationSec": 1450 }
  ],
  "visits": [
    { "clientEventId": "v-1731990100-07", "domain": "khanacademy.org",
      "visitedAt": "2026-11-19T09:40:00Z", "source": "DNS", "blocked": false }
  ],
  "blockedAttempts": [
    { "clientEventId": "b-1731990200-02", "kind": "APP", "subject": "com.example.shortvideo",
      "reason": "APP_BLOCKED", "occurredAt": "2026-11-19T09:45:00Z" }
  ]
}
```
**Response**
```json
200
{ "batchId": "8d3c…", "accepted": { "sessions": 1, "visits": 1, "blockedAttempts": 1 },
  "duplicates": 0, "rejected": [], "serverTime": "2026-11-19T10:00:01Z", "desiredPolicyVersion": 14 }
```
A replay of the same `batchId` returns the identical `200` body with `"duplicates": 3`.

**Policy conflict — response**
```json
409
{ "error": { "code": "POLICY_VERSION_CONFLICT", "status": 409, "requestId": "req_…",
  "message": "Policy changed since you loaded it.",
  "details": [{ "path": "baseVersion", "issue": "expected 15, got 14" }] },
  "latest": { "version": 15, "document": { "…": "…" } } }
```

### 8.4 Express implementation notes
- `helmet`, `cors` (explicit origin allow-list for dashboard), `express.json({ limit: '256kb' })` (batch route uses a larger limit + gzip), `pino-http` with `redact: ['req.headers.authorization','req.body.password','req.body.code','req.body.refreshToken']`.
- A single `validate({ body, query, params })` middleware wrapping Zod; handlers receive typed data.
- Central error handler maps `ZodError`→400, `HttpError`→status, everything else→500 with `requestId`.
- Express 5 async handlers can `throw`/reject without wrappers ✅.
- Generate an OpenAPI document from the Zod schemas in CI (optional) and publish to `docs/API_DOCUMENTATION.md`.

---

## 9. Real-Time Communication and Synchronisation

### 9.1 Mechanism responsibilities (normative)

| Responsibility | Mechanism | Why | Failure mode and fallback |
|---|---|---|---|
| **Notify device that policy changed** | **FCM data message** (Android) / **APNs** (iOS) / `chrome.alarms` poll (browser) | OS-sanctioned wake-up; works when app is not running (subject to OEM limits) | Not guaranteed. Fallback: heartbeat reply contains `desiredPolicyVersion`; WorkManager periodic (≥15 min); sync on app foreground, on boot, on connectivity change. |
| **Deliver the actual policy** | **HTTPS pull** `GET /devices/:id/policy` (`If-None-Match`) | Authenticated, cacheable, sized, retryable; push payload limits (4 KB FCM) too small and unauthenticated | Retry with exponential backoff + jitter; keep last-known-good. |
| **Acknowledge** | HTTPS `POST …/acknowledge` | Needs reliable, authenticated, idempotent write | Queue in local outbox; retry. |
| **Sync activity events** | HTTPS batch uploads: when outbox ≥ N items, every ~15 min while online, on screen-off, on charger+Wi-Fi bulk | Batching saves battery; idempotent | Outbox persists across kills. |
| **Report device health** | Heartbeat every 15 min (WorkManager) + piggyback on any request + immediate on permission change | Cheap; the **absence** of heartbeats is the signal | Server marks `STALE` after `staleAfterHours`, `OFFLINE` after 2× heartbeat interval during waking hours. |
| **Live parent dashboard updates** | **WebSocket** (`/ws`) while the parent app/dashboard is open | Nice UX (see device go "in sync") | If socket drops, TanStack Query refetch on focus + polling every 30 s. |
| **Parent notifications** (limit reached, device tamper) | Expo Push / FCM / APNs to parent app + in-app list + optional email | Standard | In-app list is source of truth. |

### 9.2 Why not "just WebSockets" on the child device
Mobile OSes suspend networking in Doze/App Standby (Android) and aggressively suspend background apps (iOS). A long-lived socket in the background is unreliable and battery-expensive; Play/OEM policies discourage it. The design treats push as an **optimisation**, and **correctness never depends on it** (state reconciliation via `desired vs applied` versions).

### 9.3 Android specifics
- `FirebaseMessagingService.onMessageReceived` (high-priority data message) has a few seconds; it must only **enqueue** a `OneTimeWorkRequest` (expedited if quota allows) that performs the pull. Don't do network work inline.
- Use `collapse_key = "policy"` so only the latest wake-up is delivered when offline.
- FCM token refresh → `PUT push-token`.
- Foreground service (the enforcement loop) is separate from sync; sync must work even if foreground service is stopped.
- 🟡 **Alternatives to FCM for a fully self-hosted philosophy:** UnifiedPush; not a fit for mass-market Play distribution (needs a distributor app). Keep FCM — it is free.

### 9.4 iOS specifics
- APNs (free with developer program) for parent notifications and best-effort wake-ups; **silent pushes are throttled and can be dropped** 🟡.
- Strategy: **enforce autonomously** via `DeviceActivitySchedule`s and `ManagedSettings` shields that are already installed; policy refresh occurs on launch/foreground, Background App Refresh, and visible notifications that the user taps.

### 9.5 Offline synchronisation
- Device keeps: compiled policy (signed), outbox, local usage counters, last server-time offset.
- On reconnect: (1) refresh token if needed, (2) heartbeat (learn `desiredVersion`), (3) pull policy if changed, (4) ack, (5) drain outbox oldest-first.
- Conflict surface is tiny because only the server changes policy and devices only append activity.

### 9.6 WebSocket protocol (parent side only)
`GET /ws?token=<short-lived ws ticket>` (ticket from `POST /ws/ticket`, 60 s, single-use — avoids putting the long-lived JWT in a URL). Messages: `{"t":"device.sync","deviceId":"…","applied":14}`, `{"t":"alert","kind":"LIMIT_REACHED","childId":"…"}`. Server broadcasts through an in-process hub (single instance); when scaling horizontally add Redis pub/sub (§11).

---

## 10. Security and Privacy

> This product processes children's activity data. Treat privacy as a **feature requirement**, not a compliance afterthought. This section is engineering guidance, **not legal advice**; obtain legal review before any public launch.

### 10.1 Authentication (parents)
- **Passwords:** argon2id (target ≈ 100–250 ms on the server; tune memory/time params 🟡 per OWASP guidance), per-user salt built in, optional server-side pepper from env.
- **Access JWT** 15 min (`EdDSA` or `HS256` with strong secret; prefer asymmetric so the worker/ws can verify without the signing secret). **Refresh token** opaque 256-bit random, stored **hashed (SHA-256)**; rotation on every use; `tokenFamily` revoked on reuse detection.
- Login throttling + generic errors; optional TOTP 2FA post-MVP (strongly recommended before public launch).
- Email verification required before pairing a device.

### 10.2 Authorisation and data isolation
- Roles: `OWNER` (billing/deletion/members), `GUARDIAN` (policies, devices, reports), `VIEWER` (reports only). **Child and device are not roles** — they are principals with limited tokens.
- **Family isolation invariant:** every repository query is parameterised by `familyId` derived from the *authenticated principal's memberships*, never directly from client input. Add a test suite that, for every endpoint, tries a second family's token against the first family's ids and expects `404` (automated "IDOR sweep" in CI).
- Optional later: Postgres Row-Level Security with `SET LOCAL app.family_id`.

### 10.3 Device authentication and secure pairing
**Pairing flow**
1. Parent (authenticated) creates `DevicePairing` → server generates an 8-char Crockford-base32 code (~40 bits) + QR (`https://app.example/pair?c=<code>&v=1`); stores **hash** only; TTL 10 min; single-use; max 5 attempts; per-IP rate-limit.
2. Child device (on first run, after the **child-visible consent screen**) submits the code with its descriptor and optional **public key** generated in **Android Keystore / iOS Secure Enclave**.
3. Server consumes the pairing atomically (`UPDATE … WHERE consumedAt IS NULL AND expiresAt > now() RETURNING`) and issues device credentials.
4. Parent app shows "Device X paired" via push/WS and lets the parent confirm; unconfirmed devices stay `PENDING` (no policy delivered) until confirmed — blocks a malicious third party who shoulder-surfs a code.

**Device tokens:** 60-min JWT + rotating opaque refresh token (stored in `EncryptedSharedPreferences`/Keystore-wrapped; iOS Keychain). **Hardening (Phase 13):** bind requests to the device key — client signs a challenge/nonce or each request body hash (`DPoP`-style 🟡); stolen refresh tokens become useless without the key. 
**Revocation:** `DeviceSession.revokedAt`; next request → `401 DEVICE_REVOKED` → app wipes local policy/outbox and shows "This device is no longer managed".
**Integrity attestation (optional, post-MVP):** Play Integrity API / Apple App Attest to detect tampered/rooted clients; treat as a *signal*, not a gate (false positives on custom ROMs).

### 10.4 Secure policy payloads
- Compiled policy delivered **over TLS** *and* **JWS-signed** (EdDSA, `kid` header). Device verifies signature + `deviceId`, `validUntil`, monotonic `policyVersion` (reject rollback) before applying. Protects against on-device file tampering and a compromised network path/TLS-intercepting proxy.
- Signing key kept in env/secret store, rotated by adding a new `kid` (devices fetch `signingKeys` on pair/refresh; ship a bootstrap key in the app binary for recovery).
- **TLS:** HTTPS only, HSTS on dashboard, TLS ≥ 1.2 (1.3 preferred). Android `network_security_config.xml` with cleartext disabled; consider **certificate pinning** only with a pin-set including a backup pin (pinning mistakes brick the fleet) — post-MVP.

### 10.5 On-device protections (Android)
- Local PIN/biometric gate for the child app's settings/unpair (PIN set by parent during pairing; stored as salted hash).
- Store the policy in app-private storage; verify signature at load.
- **Tamper detection signals** (reported, not hidden): usage access revoked, accessibility disabled, VPN off, device admin deactivated, app force-stopped (inferred by missing heartbeat), time/timezone changed, app updated/downgraded, ADB/developer-mode on (informational), app uninstall (device-admin `onDisabled` callback, best-effort).
- No stealth: the app has a launcher icon and persistent notification; the child can see what is monitored (§10.8).

### 10.6 Audit logging
Log: login success/failure, token reuse, pairing create/redeem, device revoke, policy publish (who/when/version), exception grants, emergency locks, member changes, data exports/deletions, permission-loss events. Store `ip`, UA hash, actor. **Do not** log secrets/content. Append-only table; no UI to delete.

### 10.7 Backups, abuse prevention, input validation
- **Backups:** `pg_dump`/WAL archiving to encrypted storage (age/gpg or provider-side), tested restores (quarterly), retention ≤ 35 d, access restricted. Secrets never in backups of repos.
- **Abuse prevention:** rate limits (§8.1); max children/devices per family (e.g., 10/20); email-verification gating; captcha only if abuse appears; ability to disable an account; **anti-stalkerware stance** — product copy and flows must discourage covert use on adults: child consent screen, visible notification, no hidden mode, ToS prohibiting use on non-consenting adults, `birthYear` sanity checks (warn if "child" is adult).
- **Input validation:** Zod everywhere; normalise domains; reject oversized arrays; parameterised SQL only (Prisma); `$queryRaw` only with tagged templates.

### 10.8 Consent, transparency, and store-policy alignment
- **Child-facing transparency screen** on first run and permanently accessible: lists what is collected (app usage durations, domains looked up when filtering, blocked attempts), who can see it, retention, and how to ask a parent about it.
- **Prominent disclosure + affirmative consent** before requesting Usage Access, Accessibility, VPN, Device Admin, notification permissions (Google Play requirements 🟡 for sensitive permissions; the disclosure must precede the system dialog and be separate from the privacy policy).
- **Google Play:** policies on Accessibility API, VpnService, `QUERY_ALL_PACKAGES`, foreground service types, Data Safety form, Families policy (if targeting children — the child app is *used by* children but is a parent-managed tool; read the Families Policy and "Apps designed for children" boundaries carefully 🟡). Explicitly prepare the permissions declaration video.
- **Apple:** App Store Review Guidelines §1.3 (Kids Category) and parental-control guidance; no third-party analytics/advertising SDKs in child-facing apps; accurate privacy nutrition labels; Family Controls entitlement application text must describe the real parental-control purpose ✅.
- **Legal (verify with counsel):** COPPA (US, under-13), GDPR (esp. Art. 8 and child data), UK Age-Appropriate Code, and — since your location is India — the **Digital Personal Data Protection Act, 2023** which treats under-18s as children and requires verifiable parental consent, with restrictions on tracking/behavioural monitoring of children 🟡 (check the exemptions and the notified Rules for your use-case before launch). A demo/portfolio with your own family has far lower exposure than a public launch.
- **No third-party analytics in child apps** (no Firebase Analytics/Crashlytics by default; use self-hosted/anonymised crash reports, or Sentry with PII scrubbing, opt-in).
- **Data minimisation defaults:** domains only (not full URLs/paths/queries); no page titles from the Android DNS path; browser extension URL collection is **off by default**, opt-in per child, with a visible indicator.
- **Explicitly excluded (by design and policy):** keylogging, screenshots, microphone/camera, SMS/call/message content, notification contents (note: TimeLimit uses notification access only to *suppress* notifications of blocked apps and states it does not store contents ✅ — if you copy this idea, copy that constraint), location (not in scope), hidden app mode.

---
## 11. Scalability and Performance

### 11.1 Stage-by-stage evolution

| Stage | Users (rough) | Infrastructure | What you deliberately do **not** build yet |
|---|---|---|---|
| **S0 Local dev** | 1 | Native Postgres, `bun run dev` for api/web, physical phone via USB | Docker, Redis, CI deploys |
| **S1 Demo** | ≤ 10 families | One small VM *or* your laptop behind a free tunnel (§18); Postgres on same host; API + worker in one process; pino logs to file; Uptime check | Load balancer, replicas, Redis |
| **S2 Private beta** | 50–500 families (≈ 100–1,500 devices) | 1 API container + 1 worker container + managed/own Postgres with daily backups; separate `worker` entry point; pgBouncer *if* connections spike; basic metrics | Partitioning, read replicas |
| **S3 Public launch** | ~5k–20k devices | 2+ stateless API instances behind LB; Redis (rate-limit + WS pub/sub); Postgres with PITR; partitioning of activity tables; object storage for exports/list files; error tracking + metrics dashboards | Microservices |
| **S4 Growth** | 100k+ devices | Split ingestion into its own deployment; dedicated worker pool; read replica for reports; consider TimescaleDB/ClickHouse for analytics *if* aggregates stop being enough; regional deploys | Premature global sharding |

> Numbers are order-of-magnitude planning aids, not benchmarks. **Measure before scaling** (§15.9).

### 11.2 Back-of-envelope write load (use to sanity check)
Assume 1 device uploads one batch every 15 min while active ≈ 96/day, ~30 sessions each day-batch. 10k devices ⇒ ~1M batch requests/day ≈ 12 req/s average, maybe 100 req/s at peaks (morning/evening sync bunching) — **trivially handled by one modest API instance + Postgres**, provided uploads are batched, jittered (±20 % random delay on device), and aggregation is asynchronous. Heartbeats at 15 min add similar volume — piggy-back them on batches when possible.

### 11.3 Techniques and when to adopt

| Technique | Adopt when | Notes |
|---|---|---|
| Indexing | Day 1 | Only indexes backed by a query in §7.5. Review with `EXPLAIN (ANALYZE, BUFFERS)`. |
| Connection pooling | When > ~50 concurrent connections or serverless | Prisma pool size small (e.g., 5–10 per instance); add **pgBouncer** (transaction mode; Prisma needs `?pgbouncer=true` 🟡) at S2–S3. |
| Redis caching | S3 or if profiling shows hot reads | Candidates: compiled policy by `(deviceId, version)`, family membership lookups, rate-limit counters. Compiled policies are cacheable because versions are immutable. |
| Background jobs | Day 1 (pg-boss) | Aggregation, retention, notification fan-out, partition creation, email. Separate worker process from S2. |
| Event batching | Day 1 (client side) | Jitter, gzip, size caps. |
| Partitioning | Tables > ~50–100 M rows or retention deletes become slow | §7.6. |
| Daily aggregation | Day 1 | Dashboards read only aggregates. |
| Horizontal API scaling | S3 | Requires: stateless API (no in-memory sessions), shared rate-limit store, WS fan-out via pub/sub. |
| Worker scaling | S3 | pg-boss supports multiple workers; add `teamSize`/concurrency tuning. |
| Object storage | When exporting reports or hosting domain lists as files | S3-compatible (Cloudflare R2/MinIO). Not needed for MVP. |
| Observability | S2: structured logs + `/metrics` (prom-client) + uptime probe; S3: tracing (OpenTelemetry) | Keep resource-light on the dev machine (no local Prometheus/Grafana stack). |
| Backups/DR | S1 manual dumps; S2 automated daily + tested restore; S3 PITR | Define RPO/RTO in `SECURITY.md` (e.g., RPO 24 h, RTO 4 h at S2). |

### 11.4 Performance targets (initial SLOs — adjust after measurement)
- `GET /devices/:id/policy` p95 < 150 ms (cache-friendly).
- `POST …/activities/batch` (200 items) p95 < 400 ms.
- Dashboard `GET /usage` p95 < 300 ms (aggregates only).
- Policy publish → device applied: median < 30 s when FCM works; ≤ 20 min worst case via fallback polling.
- Android enforcement: block screen appears < 500 ms after a blocked app enters foreground (target; verify per device).
- Child app battery impact: < 3 %/day attributable (measure with `adb shell dumpsys batterystats`).

---

## 12. Open-Source Project Research

### 12.1 Method and honesty statement
I searched GitHub/GitLab/F-Droid-derived pages during preparation. **What I could confirm** is marked ✅ with the evidence type. **What I could not confirm** (licence type, last commit date, maintenance state) is marked **"NOT VERIFIED"** — I deliberately did not fill those from memory. *Before reusing any code, open the repository, read `LICENSE`, check the last commit date, issues and releases.* Copyleft (GPL/AGPL) code **cannot be copied into a closed-source/commercial product** without releasing your product under a compatible licence; for a commercial path prefer *studying* GPL code and *reusing* MIT/Apache/MPL code.

### 12.2 Genuine parental-control / enforcement projects

| Project | URL | Language | What it does | Architecture | Licence | Last activity | Use for | Limitations |
|---|---|---|---|---|---|---|---|---|
| **TimeLimit / "Open TimeLimit"** (Jonas Lochmann) | https://gitlab.com/timelimit.io/opentimelimit-android ✅ (repo URL from F-Droid metadata) | Kotlin/Java (🟡) | Real parental control: app blocking, per-app and daily limits, time rules, blocked categories, device-owner features, optional sync server for parent↔child | Child app enforces locally; sync server holds family state; parent app/console | **GPL-3.0-only** ✅ (F-Droid build metadata) | NOT VERIFIED | **Study first** (best reference for Android enforcement patterns: usage detection, notification suppression, home-press via accessibility, device-owner paths). Do not copy into a closed product. | Blocks apps, **not websites** ✅ (user review on AlternativeTo); GPL; **Play Store build hides device-owner features behind a build flag** ✅ (per wiki of a derivative project). |
| **timelimit-parent** (mpashka, derivative console) | https://github.com/mpashka/timelimit-parent ✅ | TypeScript/Node ✅ | Web/CLI parent console for a TimeLimit sync server; documents ADB `dpm set-device-owner` flow | Talks the TimeLimit server protocol | **AGPL-3.0** ✅ (README) | NOT VERIFIED | Reading the **device-owner provisioning steps** and protocol shape. | Third-party derivative; depends on patched server/app; small project. |
| **Acutis Firewall** (phasnox) | https://f-droid.org/en/packages/com.acutis.firewall/ ✅ (follow "Source Code" link from page) | NOT VERIFIED | On-device blocking of adult/malware domains, PIN-protected settings, auto-start, opt-in blocklist download | Local filtering (likely VpnService — verify in source) | **MIT** ✅ (F-Droid page) | v1.0.5 listed ✅ (date NOT VERIFIED) | **Reuse/study candidate** for DNS-filter structure and permissive licence. | Small, young; no remote parental management. |
| **KidSafe** (xMansour) | https://github.com/xMansour/kidSafe ✅ | Java ✅ | Remote app blocking, screen-time, installed-apps, geofence; **also SMS/calls/contacts access** ✅ | Firebase Auth/DB/Storage backend ✅ | NOT VERIFIED | NOT VERIFIED | Study UI/flow ideas only. | **Do not replicate SMS/call/contacts collection** — conflicts with this blueprint's privacy stance and Play policy. Firebase-coupled. |
| **KidShield** (Yousaf1204) | https://github.com/Yousaf1204/KidShield ✅ (via DEV post) | Android/Java-Kotlin (NOT VERIFIED) | App blocker, location, call/SMS logs; "educational use only" ✅ | Foreground service polling every ~2 s + AlarmManager sync, Firebase RTDB ✅ | NOT VERIFIED | NOT VERIFIED | Anti-pattern study (2 s polling; invasive logs). | Educational; battery-hungry design; invasive data. |
| **Screen Time Calculator** (rati-bar/Android-app) | https://github.com/rati-bar/Android-app ✅ | Kotlin + Compose ✅ | Child earns screen time by tasks; **Device Owner kiosk/anti-bypass**, Play Integrity, WorkManager, Firebase ✅ | `app-parent` + `app-child`, Cloud Functions ✅ | NOT VERIFIED | 33 commits seen ✅ | Study Device-Owner kiosk + anti-bypass ideas. | Small hobby project; README has placeholder repo URL (immature). |
| **Times-up (Flutter)** (JordyHers-org) | https://github.com/JordyHers-org/Times-up-flutter ✅ | Dart ✅ | Parental app collecting location/app data to Firebase ✅ | Flutter + native plugins ✅ | A LICENSE file exists ✅ (type NOT VERIFIED) | Indexed ~ recently by ecosyste.ms (not a commit date) | Cross-platform UI inspiration. | Flutter, not RN; location tracking. ~114 stars ✅. |
| **YouTubeWhitelist** (degipe) | https://github.com/degipe/YouTubeWhitelist ✅ | Android | Parent whitelists YouTube channels/videos for kids | App-local | NOT VERIFIED | NOT VERIFIED | Niche idea: allow-list content mode. | Single-purpose. |

### 12.3 DNS / network filtering building blocks

| Project | URL | Language | Function | Licence | Verdict |
|---|---|---|---|---|---|
| **RethinkDNS + Firewall** (celzero) | https://github.com/celzero/rethink-app ✅ | Kotlin (~93 %) + Go core ("firestack") ✅ | VpnService firewall, DoH/DoT/DNSCrypt client, blocklists, connection tracker ✅ | **Apache-2.0** ✅ (README of a fork) — confirm in upstream `LICENSE` | **Best study/reuse candidate** for a non-GPL VpnService DNS filter architecture. Heavy (Go core, many features) — extract ideas, don't fork whole. Maintenance: NOT VERIFIED (a mirror showed "synced ~1 year ago", which is not a commit date). |
| **NetGuard** (M66B) | https://github.com/M66B/NetGuard (README seen via fork) ✅ | Java | No-root VpnService firewall per app ✅ | **GPLv3** ✅ | Study only (copyleft). FAQ confirms Android cannot chain VPN services ✅ — a key constraint for your DNS filter. |
| **Blokada** | NOT VERIFIED in this session | Kotlin | DNS-level blocker | NOT VERIFIED — licence/status reportedly changed across versions ✅ (users on a fediverse thread say newer versions went paid/cloud) | Only after you personally check the repo's current licence and activity. |

*From general knowledge — NOT VERIFIED in this session; check before use:* **AdGuard Home** (GPL-3.0, Go; network-wide DNS filtering with parental-control toggles, good for a self-hosted *server-side* DNS option), **Pi-hole** (EUPL-1.2), **StevenBlack/hosts** and similar curated blocklists (MIT for the aggregator; **each upstream source list has its own licence**), **UT1 Capitole** domain categories (an academic category blocklist — check the current licence/attribution terms; relevant for `WebsiteCategory` data). For blocklist data, **record licence and attribution per list** in `WebsiteCategory.sourceLicense`.

### 12.4 Browser-extension references
I did **not** verify any specific open-source *parental-control* browser extension. Use primary references instead: Chrome's official `declarativeNetRequest` docs and the `GoogleChrome/chrome-extensions-samples` repository (🟡 Apache-2.0 — verify), and MDN's WebExtensions compatibility tables for Firefox. Generic site-blocker/self-control extensions exist but are **productivity tools, not parental controls** (the child can simply disable them) — do not mistake them for a model of enforcement.

### 12.5 Self-control vs genuine parental control
A community thread (Privacy Guides, 2026) ✅ shows that FOSS accessibility-based blockers (e.g., "Scroll Block", "DetoxDroid") target **self-control**: whoever holds the device can undo them. Genuine parental control requires an authority the child cannot override (Device Owner, Family-Sharing-authorised Screen Time, managed browser policy). Treat self-control repos as UI inspiration only.

### 12.6 Recommendations
1. **Read the TimeLimit source** for Android enforcement patterns, but **write your own implementation** (licence + architecture mismatch).
2. **Study RethinkDNS** for VpnService packet/DNS handling; decide whether a minimal DNS-only VpnService (parse UDP/53, answer NXDOMAIN, forward the rest) written from scratch is simpler — it usually is, ~500–800 lines.
3. Avoid inheriting any design that collects SMS/calls/location.

---

## 13. Development Environment Setup (Nobara Linux)

> Commands assume Nobara (Fedora-based, `dnf`). Package names are 🟡 — if one fails, `dnf search`. Run as your normal user; `sudo` where shown.

### 13.1 Base tools
```bash
sudo dnf upgrade --refresh -y
sudo dnf install -y git curl unzip zip tar gcc gcc-c++ make openssl-devel \
  java-17-openjdk-devel android-tools postgresql-server postgresql-contrib watchman
# watchman is optional (Metro file watching); skip if unavailable.
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
```

### 13.2 Node (via fnm) and Bun
```bash
curl -fsSL https://fnm.vercel.app/install | bash
exec $SHELL
fnm install 22 && fnm default 22
node -v        # v22.x

curl -fsSL https://bun.sh/install | bash
exec $SHELL
bun -v
```
Add a `.node-version` file (`22`) at the repo root.

### 13.3 Android SDK **without Android Studio**
```bash
mkdir -p ~/Android/Sdk/cmdline-tools && cd ~/Android/Sdk/cmdline-tools
# Download "Command line tools only" for Linux from:
#   https://developer.android.com/studio#command-line-tools-only
# (the filename contains a build number that changes: commandlinetools-linux-XXXXXXX_latest.zip)
unzip ~/Downloads/commandlinetools-linux-*_latest.zip
mv cmdline-tools latest          # must end up as .../cmdline-tools/latest/bin/sdkmanager

# ~/.bashrc  (or ~/.zshrc)
cat >> ~/.bashrc <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
EOF
source ~/.bashrc

yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
sdkmanager --list_installed
```
- Use the compile/target SDK that your chosen Expo SDK's template specifies (🟡 SDK 55/56 era projects use API 36). NDK/CMake: let Gradle auto-install them on first build (works when licences are accepted and `ANDROID_HOME` is writable), or install exactly the version the build error names via `sdkmanager "ndk;<version>"`.
- **Do not install the emulator or system images.** (`emulator` and `system-images;*` are not needed; saves GBs and RAM.)
- If `adb` from `android-tools` and from `platform-tools` conflict, keep only the SDK one first in `PATH` (`which adb`).

### 13.4 Gradle and JVM tuning (critical for 8 GB)
`~/.gradle/gradle.properties` (global, applies to every project):
```properties
org.gradle.daemon=true
org.gradle.parallel=false
org.gradle.workers.max=2
org.gradle.caching=true
org.gradle.configuration-cache=true
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m -XX:+UseSerialGC -Dfile.encoding=UTF-8
kotlin.daemon.jvm.options=-Xmx1g
kotlin.compiler.execution.strategy=in-process
android.useAndroidX=true
android.enableJetifier=false
```
In the Expo project's `android/gradle.properties` (or via the Expo `expo-build-properties` plugin) limit ABIs during development:
```properties
reactNativeArchitectures=arm64-v8a
```
(Almost all modern phones are arm64; building 4 ABIs quadruples native compile time and RAM.)
Stop the daemon when you are done: `./gradlew --stop`. Prefer `kotlin.compiler.execution.strategy=in-process` to avoid a separate Kotlin daemon (trade-off: Gradle daemon holds more).

### 13.5 Postgres (native, not Docker)
```bash
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql
sudo -u postgres psql <<'SQL'
CREATE USER kidguard WITH PASSWORD 'dev_only_change_me';
CREATE DATABASE kidguard OWNER kidguard;
SQL
# Allow password auth on localhost (Fedora defaults to ident for TCP):
sudo sed -i 's/\(host.*127.0.0.1\/32\s*\)ident/\1scram-sha-256/; s/\(host.*::1\/128\s*\)ident/\1scram-sha-256/' /var/lib/pgsql/data/pg_hba.conf
sudo systemctl restart postgresql
psql "postgresql://kidguard:dev_only_change_me@localhost:5432/kidguard" -c "select version();"
```
Cap Postgres memory in `/var/lib/pgsql/data/postgresql.conf` (dev): `shared_buffers=128MB`, `work_mem=8MB`, `max_connections=40`. Docker Compose is only worth it for reproducible CI/other contributors (`infrastructure/docker-compose.yml`, Postgres only; use Podman if you prefer). Do not run Docker Desktop-style stacks on 8 GB alongside Gradle.

### 13.6 Create the workspace
```bash
mkdir kidguard && cd kidguard && git init
cat > package.json <<'EOF'
{ "name": "kidguard", "private": true,
  "workspaces": ["apps/*", "packages/*"],
  "scripts": {
    "dev:api": "bun --cwd apps/api run dev",
    "dev:web": "bun --cwd apps/dashboard run dev",
    "typecheck": "bun run --filter '*' typecheck",
    "test": "bun run --filter '*' test"
  } }
EOF
mkdir -p apps packages infrastructure docs
bun create expo-app apps/child-mobile      # follow prompts; choose the default template (current SDK)
```
(Naming: `kidguard` is a placeholder; check trademark/name availability before publishing.)

### 13.7 Build and run the Android child app on a physical device

**Phone:** Settings → About → tap *Build number* ×7 → Developer options → enable **USB debugging** (and, on some OEMs, "Install via USB" / "USB debugging (Security settings)").

```bash
adb devices                      # should list your device as "device" (accept RSA prompt on phone)
# If it says "no permissions" or is missing: add a udev rule
echo 'SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:ff4200:*", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
adb kill-server && adb start-server
```
Build and install (local Gradle, no Android Studio, no EAS cloud):
```bash
cd apps/child-mobile
bunx expo install expo-dev-client
bunx expo prebuild --platform android            # generates android/ from app.config + plugins
bunx expo run:android --device                    # builds debug APK, installs, starts Metro
# later iterations (JS-only changes need no rebuild):
bunx expo start --dev-client
adb reverse tcp:8081 tcp:8081                     # Metro over USB
adb reverse tcp:3000 tcp:3000                     # your local API as http://localhost:3000 on the phone
```
Manual APK path (useful when you only changed Kotlin):
```bash
cd android && ./gradlew :app:installDebug         # build+install
./gradlew assembleRelease                          # signed release needs a keystore (keytool -genkeypair …)
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### 13.8 Logs and debugging
```bash
adb logcat -c && adb logcat --pid=$(adb shell pidof -s com.kidguard.child)   # app logs only
adb logcat -s KidGuard:V ReactNativeJS:V AndroidRuntime:E                      # tags (use a TAG constant "KidGuard")
adb shell dumpsys usagestats | head -50                                         # usage stats state
adb shell dumpsys package com.kidguard.child | grep -i permission
adb shell appops get com.kidguard.child GET_USAGE_STATS
adb shell cmd appops set com.kidguard.child GET_USAGE_STATS allow              # dev shortcut for usage access
adb shell dumpsys deviceidle                                                    # Doze state
adb shell am force-stop com.kidguard.child                                      # test kill behaviour
adb shell dumpsys batterystats --reset ; …later… adb shell dumpsys batterystats com.kidguard.child
```
- **React Native / JS debugging:** press `j` in the Expo CLI to open React Native DevTools (Hermes). `console.log` shows in Metro and logcat.
- **Kotlin debugging without Android Studio:** (1) logcat-first debugging with a single `TAG`; (2) JVM unit tests on the host (`./gradlew :app:testDebugUnitTest`, or the module's test task) for evaluator/schedule/interval logic — this is where 80 % of bugs should be caught; (3) attach a JDWP debugger: 
```bash
adb forward tcp:8700 jdwp:$(adb shell pidof -s com.kidguard.child)
jdb -attach localhost:8700          # or use VS Code with the "Kotlin"/"Debugger for Java" attach config to localhost:8700
```
- **Instrumented tests** on the physical device: `./gradlew connectedDebugAndroidTest`.
- **Device Owner dev provisioning** (spare/test phone only, **no Google account on it**):
```bash
adb shell dpm set-device-owner com.kidguard.child/.admin.AdminReceiver
# To make removal possible during development, mark the DEBUG manifest android:testOnly="true", then:
adb shell dpm remove-active-admin com.kidguard.child/.admin.AdminReceiver
```
(Without `testOnly`, removing a device owner usually requires a factory reset — **do not experiment on your daily phone**.)

### 13.9 Avoiding exhaustion of 8 GB RAM

| Process | Typical RAM | Tip |
|---|---|---|
| Gradle daemon (+ Kotlin) | 1.5–2.5 GB | Capped via `-Xmx2g`; `./gradlew --stop` when idle |
| Metro bundler | 0.5–1 GB | Stop when not testing the app |
| VS Code (with TS server) | 0.8–1.5 GB | Disable unused extensions; or Neovim + `typescript-language-server` (lighter) |
| Postgres | 0.2–0.4 GB | Config above |
| Browser (dashboard dev) | 1–2 GB | Use one profile; close tabs |
| Node API (tsx watch) | 0.2–0.3 GB | – |

Workflow rules: (1) **Do not run API, Metro, Gradle build and VS Code + browser at the same time** during native builds — do the native build, then stop Gradle. (2) Keep **zram** on (`zramctl`, `swapon --show`; Fedora enables it by default) and add a 8 GB swapfile as a safety net: `sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`. (3) Most iteration should be **JS hot reload** and **JVM unit tests**, which are cheap; native rebuilds should be occasional. (4) Use `tsc --noEmit -w` only in the package you are editing. (5) Set `NODE_OPTIONS=--max-old-space-size=1536` for heavy tools.

### 13.10 Environment variables
- `apps/api/.env` (git-ignored), `.env.example` committed with dummy values. Validate on startup with Zod (`env.ts`) — **crash early** on missing secrets.
- Mobile apps: public values only via `EXPO_PUBLIC_*` (API base URL); **never** put secrets in the app. Dev/prod API URL via `app.config.ts` + `process.env.APP_ENV`.
- Tools: `bun --env-file=.env` or `dotenv`; `direnv` optional.
- Secrets to generate locally: `JWT_PRIVATE_KEY`, `POLICY_SIGNING_KEY` (Ed25519): `openssl genpkey -algorithm ED25519 -out policy_signing.pem`.

### 13.11 iOS from Linux — what is and isn't possible
- **Linux can:** write the shared TypeScript, backend, and even the Swift sources as text; run Swift on Linux (`swift` toolchain) for *pure-logic* unit tests (e.g., the evaluator port) — **but not** FamilyControls/DeviceActivity/ManagedSettings (Apple-only frameworks).
- **Requires macOS + Xcode:** building the app, creating extension targets, signing/provisioning, Simulator, device installs, TestFlight upload (Xcode/`xcrun`/Transporter). Apple's licence prohibits macOS on non-Apple hardware (no Hackintosh/VM route).
- **Practical paths (cheapest first):** (1) **Used Apple-silicon Mac mini/MacBook Air** (a one-time cost; the only comfortable route for extension debugging); (2) **cloud Mac** rental hourly/monthly + a **physical iPhone** attached to a colleague/friend's Mac for device runs; (3) **EAS Build** (Expo's cloud builds) 🟡 can compile and sign iOS binaries from Linux, with free-tier queue/limits — good for CI builds, **not** for debugging Screen Time extensions.
- **Family Controls specifics:** Screen Time authorisation is effectively **physical-device only** (test on a real iPhone with a Family Sharing child Apple ID). Request the **distribution entitlement early** (§19, Phase 0) because approval time is unbounded ✅.
- **Prerequisites purchases:** Apple Developer Program (USD 99/yr 🟡); Google Play Console (USD 25 one-time 🟡).

### 13.12 Editor setup (lightweight)
- VS Code extensions: ESLint, Prettier (or Biome), Prisma, Tailwind CSS IntelliSense, Kotlin (fwcd) 🟡, Gradle for Java 🟡, EditorConfig. Disable the Java/Kotlin language servers unless editing native code.
- Neovim: `typescript-tools.nvim` or `vtsls`, `kotlin_language_server` (fwcd) via LSP, `nvim-dap` + Java debug adapter for JDWP attach. Keep native Kotlin small to avoid LSP pain.
- Format/lint: **Biome** (single fast binary, low RAM) for TS/JSON; `ktlint` via Gradle for Kotlin.

---

## 14. Monorepo and Folder Structure

### 14.1 Layout

```
kidguard/
├─ apps/
│  ├─ api/                         # Express 5 + Prisma + ws + pg-boss (Node 22)
│  │  ├─ src/
│  │  │  ├─ main.ts                # http server + ws
│  │  │  ├─ worker.ts              # pg-boss worker entry (same codebase)
│  │  │  ├─ config/env.ts
│  │  │  ├─ http/ (middleware, error handler, rate limits)
│  │  │  └─ modules/
│  │  │     ├─ auth/ family/ devices/ policy/ activity/ analytics/ notifications/ catalog/ audit/
│  │  │     └─ policy/compilers/{android,ios,browser}.ts
│  │  ├─ prisma/ (schema.prisma, migrations/, sql/ for partition & raw migrations)
│  │  └─ test/
│  ├─ dashboard/                   # React + Vite + Tailwind + Recharts
│  ├─ parent-mobile/               # Expo (no native modules)
│  ├─ child-mobile/                # Expo dev-build: ONE app for Android + iOS
│  │  ├─ app/ (Expo Router screens)
│  │  ├─ modules/
│  │  │  ├─ enforcement-android/   # Kotlin: Expo module + services + engine (+ JVM tests)
│  │  │  └─ enforcement-ios/       # Swift: Expo module + extension sources
│  │  ├─ plugins/                  # config plugins (manifest entries, extension targets)
│  │  └─ app.config.ts
│  └─ browser-extension/           # MV3 TS, builds chrome/ edge/ firefox/ targets
├─ packages/
│  ├─ shared-types/                # DTO types, enums (pure TS)
│  ├─ validation/                  # Zod schemas (source of truth for request/response)
│  ├─ policy-contracts/            # PolicyDocument types, Compiled* types, golden test vectors
│  ├─ api-client/                  # typed fetch client used by dashboard, parent, child JS, extension
│  └─ config/                      # tsconfig bases, biome config
├─ infrastructure/                 # docker-compose.yml (postgres), deploy scripts, backup scripts
├─ docs/                           # all .md docs, ADRs
├─ .github/workflows/
├─ package.json  bun.lock  biome.json  .node-version
└─ PROJECT_BLUEPRINT.md
```

*Deviation from your list:* `apps/android-child` + `apps/ios-child` are merged into `apps/child-mobile` (§0.3 #1). If, after Phase 5, the Android child app proves to need almost no RN UI, split it into a native Kotlin app — the shared packages and API contract remain unchanged, so the decision is cheap to reverse. Record as ADR-003.

### 14.2 What is shared vs platform-specific

| Shared (pure TS) | Platform-specific (never shared) |
|---|---|
| Request/response Zod schemas, error codes | Kotlin enforcement engine, services, Room schema |
| Policy types & JSON schema, golden test vectors | Swift Screen Time module and extensions |
| API client (fetch-based) | Extension DNR rule application code |
| Date/timezone helpers (use `Intl`/`date-fns-tz`) | Native build systems (Gradle/Xcode) |
| UI components → **only** between `parent-mobile` and `child-mobile` if truly generic (otherwise copy; avoid a premature `ui` package) | Push-token acquisition per platform |

**Kotlin parity with TS contracts:** generate Kotlin data classes from the JSON Schema of `PolicyDocument`/`Compiled*` (e.g., `quicktype` 🟡 or a small script) in CI to prevent drift — or hand-write them and enforce parity with the golden vectors (§6.9).

### 14.3 Avoiding over-abstraction
No generic repository layer, no DI container, no DTO mappers. Rules: (1) module `db.ts` returns Prisma types; (2) handlers map to response shapes inline; (3) introduce a `service` file only when a handler needs more than ~40 lines of orchestration or the logic is reused by two entry points (HTTP + worker).

### 14.4 Metro/monorepo gotchas
- Expo's default config detects workspaces in recent SDKs ✅ (verify in Phase 1 by importing `@kidguard/shared-types` in `child-mobile`).
- Build shared packages to **plain ESM + `.d.ts`** or point `exports` at TS sources and let Metro/Vite transpile (simpler in dev; consistent `moduleResolution: "bundler"`).
- Keep **one copy of `react`/`react-native`** (hoisting issues are the #1 monorepo failure); pin versions in root `overrides`/`resolutions`.

---

## 15. Testing Strategy

### 15.1 Pyramid and tooling

| Layer | Tool | Scope | Runs |
|---|---|---|---|
| Unit (TS) | Vitest (or `bun test`) | Policy validation/compiler, schedule math, token logic | Every save/CI |
| Unit (Kotlin, JVM) | JUnit5 via Gradle | `EnforcementEngine`, interval merger, schedule math, outbox logic (no Android classes) | CI + local |
| API integration | Vitest + Supertest against a **real Postgres** (separate `kidguard_test` DB; reset per file via transaction/truncate) | All endpoints, auth, IDOR sweep | CI |
| DB tests | Prisma migrations apply from scratch; constraint/idempotency tests; partition SQL tests | CI |
| Contract tests | Golden policy vectors executed by TS, Kotlin (and Swift on Mac) | CI |
| Android instrumented | `connectedDebugAndroidTest` on physical device | Usage access, overlay, VPN service smoke | Manual/nightly on your phone |
| E2E (manual scripted) | Checklists in §15.4 | Real device + backend | Per milestone |
| Browser extension | Vitest for logic; Playwright with `--load-extension` (Chromium) 🟡 for E2E | Rule application, blocked page | CI (headed Chromium needs xvfb) |
| Security | `npm audit`/`bun audit`-style, `semgrep` (OSS rules), OWASP ZAP baseline against staging, secrets scan (`gitleaks`) | CI + pre-release |
| Performance | `k6` or `autocannon` against ingest + policy fetch | Before S2 |

### 15.2 Backend test cases that must exist
- **Auth:** register/login happy path; duplicate email; brute-force lockout; refresh rotation; **refresh reuse revokes family**; expired access; password reset single-use; email-verification gating.
- **Isolation (IDOR sweep):** for each `:childId/:deviceId/:familyId` route, a token from another family → `404`.
- **Pairing:** code single-use; expiry; attempts cap; concurrent redeem race (only one succeeds); revoked device → `401 DEVICE_REVOKED`.
- **Policy:** schema validation matrix; semantic rules (cannot block own app); `baseVersion` conflicts; version monotonicity; compile output per device descriptor; unsupported-rule warnings; signature verifies with published key; `304` when `If-None-Match` matches.
- **Ingest:** duplicate batch → same response, no duplicate rows; out-of-range timestamps rejected; oversized batch 413; partial rejects reported; aggregation idempotent (run twice → same totals); midnight split; overlapping sessions merged; late batch updates yesterday.
- **Retention jobs:** purge deletes only expired rows; deletion ledger written.

### 15.3 Android native testing
- **JVM tests for pure logic** (cheapest, most valuable): schedule crossing midnight, DST dates (`Asia/Kolkata` has none; add `America/New_York` vectors), limit + exception arithmetic, clock-offset handling, intervals merging, outbox ordering.
- **Instrumented tests (device):** permission-state detectors; Room migrations; VPN service starts/stops; DNS parser against captured packets (store `.pcap`-derived byte fixtures).
- **Manual matrix** — test on ≥ 2 devices across **different OEMs** (e.g., one near-stock, one MIUI/One UI/ColorOS) and 2 Android versions if possible.

### 15.4 Feature test procedures and acceptance criteria

| Feature | How to test | Acceptance criteria |
|---|---|---|
| **App blocking** | Block `com.android.chrome` from dashboard; open it on child phone | Block screen shown ≤ 500 ms after foreground; app cannot be used via recents; `BlockedAttempt` recorded and visible in dashboard ≤ 2 min; works with app killed from recents and after reboot (service restarts). |
| **Per-app limit** | Set 2-min limit on a test app; use it for 2 min | Blocked within ±30 s of limit; usage total matches `dumpsys usagestats` within ±1 min/hour; limit resets at local midnight. |
| **Total screen-time limit** | Set 5-min limit; use mixed apps | Total counts all non-allowlisted apps; phone dialer exempt; lock appears; parent receives "limit reached" push ≤ 1 min after reconnect. |
| **Schedule (bedtime)** | Set schedule starting in 3 min | Blocks at start ±10 s; always-allowed apps still work; ends correctly; cross-midnight case verified with test vectors. |
| **Time tampering** | Change clock +2 h / change timezone | Detected within 10 s; parent notified; enforcement uses corrected time (no bypass). |
| **Website blocking (DNS)** | Block `example.com`; visit in Chrome/Firefox | NXDOMAIN/blocked page; allow-list overrides category; **DoH/Private DNS bypass** documented and (Tier 2) mitigated; VPN-off detected and reported. |
| **Background execution** | Screen off 30 min, battery saver on, app swiped away, reboot | Enforcement resumes ≤ 30 s after boot/unlock; heartbeat resumes ≤ 15 min; on aggressive OEMs the in-app guide fixes it, verified. |
| **Policy sync** | Edit policy while device online / offline / FCM blocked | Online: applied ≤ 30 s; offline: applied on reconnect ≤ 60 s; ack recorded; parent UI shows "in sync". Rollback attempt (older version) rejected. |
| **Offline enforcement** | Airplane mode for 24 h | All locally cached rules still enforced; outbox retained; after reconnect uploads without duplicates. |
| **Tamper detection** | Revoke usage access / disable accessibility / turn off VPN / force-stop | Parent alert within 15 min (or when device returns); capability states reflect reason. |
| **Device revoke** | Revoke from dashboard | Device receives `DEVICE_REVOKED` on next contact, wipes local data, shows unmanaged state; server rejects further uploads immediately. |
| **Browser extension** | Load unpacked extension, set rules | Blocked page shown; rules persist after browser restart & offline; service-worker kill/restart does not lose state; blocked attempt visible. |
| **iOS (Mac required)** | Real iPhone + Family Sharing child | Shield applied for selected tokens; schedule shield begins/ends without app running; threshold event triggers shield; documented as best-effort given reported false positives. |

### 15.5 Offline synchronisation tests
Chaos scenarios in integration tests: drop network mid-upload (retry → no dupes), kill app mid-write (outbox integrity), server returns 500 for N attempts (backoff), clock skew ±1 day, token expiry while offline, policy fetched twice concurrently.

### 15.6 Security tests
IDOR sweep; JWT tampering (alg none, wrong `typ`, wrong `kid`); refresh-token replay; SQLi/Zod fuzz (`fast-check` 🟡) on inputs; rate-limit enforcement; pairing brute-force simulation; signature-verification negative tests on device (modified payload, replayed old version); log redaction test (assert secrets absent in logs); dependency audit; ZAP baseline.

### 15.7 Performance tests
`k6` scenario: 1,000 virtual devices each posting 30-item batches with jitter for 10 min; assert p95 and DB CPU; verify aggregation queue drains; `EXPLAIN` the top queries.

### 15.8 CI (GitHub Actions free tier 🟡 limits apply)
Jobs: `lint+typecheck`, `unit` (TS), `api-integration` (service container Postgres), `kotlin-unit` (Gradle JVM tests only; cache `~/.gradle`), `extension-build`. **Do not** build full Android APKs on every push (slow/expensive on free minutes); build release APK on tags only.

### 15.9 Observability for tests/perf
`pg_stat_statements`, pino request timing, `prom-client` histograms — enable in test/staging only.

---
## 16. Development Roadmap and Milestones

### 16.1 Planning assumptions
- One developer, **~10–15 focused hours/week**. Durations are **ranges at that pace**, include testing, and exclude waiting on third parties (Apple entitlement, store reviews). Treat as planning estimates, not commitments; re-estimate after each phase.
- Each milestone `M<phase>.<n>` is independently demonstrable and testable. Do not start a phase until the previous phase's *acceptance criteria* pass.
- **Parallel lead-time items** start in Phase 0 and run in the background: Apple Developer enrolment + Family Controls distribution entitlement request; buying/obtaining a spare Android phone for Device Owner experiments; (later) Mac access.

### 16.2 Dependency graph

```mermaid
flowchart LR
  P0[P0 Research + Spikes] --> P1[P1 Repo + Env]
  P1 --> P2[P2 Backend + Auth]
  P2 --> P3[P3 Family/Child/Device]
  P3 --> P4[P4 Web Dashboard]
  P3 --> P5[P5 Android Skeleton]
  P5 --> P6[P6 Usage Tracking]
  P6 --> P7[P7 App Restrictions]
  P7 --> P8[P8 Website Filtering]
  P3 --> P9[P9 Policy Sync + Offline]
  P7 --> P9
  P6 --> P10[P10 Analytics]
  P9 --> P10
  P9 --> P11[P11 Browser Extension]
  P9 --> P12[P12 iOS]
  P10 --> P13[P13 Hardening]
  P8 --> P13
  P11 --> P13
  P12 --> P13
```

**Re-ordering vs your suggestion:** the policy **data model, versioning and the sync protocol are pulled forward to Phase 3–5 as a thin vertical slice** (even a hard-coded policy fetched over HTTP), because Phases 6–8 need *something* to enforce and test against. Phase 9 then *completes* sync (FCM, offline, acks, signatures). Phase 4 (dashboard) is intentionally small.

### Phase 0 — Requirements and technical research (1–2 weeks)
- **Objective:** retire the biggest technical unknowns *before* committing code.
- **Prerequisites:** none.
- **Tasks (spikes — each produces a short note in `docs/spikes/`):**
  1. **S-AND-1 Usage events:** tiny Kotlin/Expo app reading `UsageEvents` on your phone; log foreground transitions; compare to `dumpsys usagestats`.
  2. **S-AND-2 Block screen:** show a blocking Activity/overlay when a chosen package comes to foreground; measure latency; test with/without Accessibility; note Android-version behaviour.
  3. **S-AND-3 Foreground service survival:** run 24 h on your device; record kills; test OEM battery settings.
  4. **S-AND-4 VpnService DNS:** minimal service intercepting UDP/53, answering NXDOMAIN for one domain; test Chrome with and without Secure DNS.
  5. **S-AND-5 Expo native module:** call a Kotlin function from RN via `create-expo-module --local`; confirm dev-build workflow on Linux without Android Studio.
  6. **S-IOS-1 (paper spike now, real spike later):** read Apple docs; draft the **Family Controls distribution entitlement request** text; enrol in Apple Developer Program; submit request for the **main app and each extension bundle ID** ✅ (entitlement is per-bundle).
  7. **S-WEB-1 DNR:** MV3 extension that blocks a domain via dynamic rule and persists across service-worker restarts.
  8. **S-PLAY-1:** read Play policies (Accessibility, VpnService, foreground service types, QUERY_ALL_PACKAGES, Families) and write the compliance checklist.
- **Deliverables:** `PROJECT_REQUIREMENTS.md`, `docs/spikes/*.md`, ADR-001 (modular monolith), ADR-002 (Expo + Kotlin boundary), initial risk register.
- **Acceptance:** S-AND-1..5 produce working demos on your phone; written go/no-go for Accessibility use and for DNS-via-VPN.
- **Challenges:** OEM variance; entitlement queue; Play policy interpretation.

### Phase 1 — Repository and development environment (3–5 days)
- **Objective:** reproducible workspace that builds on 8 GB.
- **Prerequisites:** P0 spike S-AND-5 done.
- **Features/Tasks:** follow §13; create monorepo skeleton (§14); configure Biome, TS base configs, `.editorconfig`, commit hooks (`lefthook` or `husky`), CI skeleton; `packages/shared-types` imported from `apps/api`, `apps/dashboard`, `apps/child-mobile` (proves Metro workspace resolution); `.env.example`; README with "first run".
- **Files:** root `package.json`, `biome.json`, `.github/workflows/ci.yml`, `docs/DEVELOPMENT_SETUP.md`.
- **Deliverables:** `bun install && bun run typecheck && bun run test` green; phone shows a hello-screen using a shared type.
- **Acceptance:** fresh clone → running within 30 min following the doc; peak RAM during native build < 6.5 GB (`free -m`).
- **Challenges:** Metro + Bun hoisting; Gradle memory.

### Phase 2 — Backend foundation and authentication (2–3 weeks)
- **Objective:** secure, tested API skeleton.
- **Prerequisites:** P1.
- **Features:** env validation, pino logging, error format, Zod validation middleware, health endpoints, Prisma + first migration (`citext`), User/Session/AuditLog, register/login/refresh/logout/password reset, rate limiting, email sender abstraction (console in dev).
- **Tasks:**
  - M2.1: server bootstrap + `/health` + error handler + request IDs.
  - M2.2: Prisma setup + migrations workflow + test DB harness.
  - M2.3: argon2id hashing, JWT (jose), refresh rotation + reuse detection.
  - M2.4: auth endpoints + validation + rate limits + audit entries.
  - M2.5: integration tests (§15.2 Auth list).
- **Files:** `apps/api/src/{main.ts,config/env.ts,http/*,modules/auth/*}`, `packages/validation/src/auth.ts`, `prisma/schema.prisma`.
- **Dependencies:** none external except Postgres.
- **Deliverables:** OpenAPI/Markdown for auth; Postman/`.http` file.
- **Acceptance:** all auth tests pass; refresh reuse revokes family; secrets absent from logs; k6 smoke 50 rps on login without errors (argon2 cost dominates — verify).
- **Challenges:** choosing argon2 parameters on a Ryzen 3; Prisma version-specific config.

### Phase 3 — Family, child and device management (2–3 weeks)
- **Objective:** tenancy + pairing + thin policy slice.
- **Prerequisites:** P2.
- **Features:** families, members (OWNER only in MVP; schema ready for invites), child profiles, pairing create/redeem, device list/detail/revoke, device JWT auth + refresh, capability report, heartbeat, **minimal Policy/PolicyVersion** with `GET/PUT /children/:id/policy` (validation of a **reduced** document: daily limit + app blocks) and `GET /devices/:id/policy` (unsigned for now).
- **Tasks:** M3.1 family+child CRUD; M3.2 pairing (hashing, TTL, attempts, atomic consume); M3.3 device auth middleware; M3.4 capability + heartbeat; M3.5 policy skeleton; M3.6 IDOR sweep test harness.
- **Files:** `modules/{family,devices,policy}/*`, `packages/policy-contracts`.
- **Acceptance:** two-family isolation sweep passes for all routes; pairing race test passes; revoked device gets `DEVICE_REVOKED`.
- **Challenges:** getting the pairing UX secure but simple; defining `DeviceDescriptor` early.

### Phase 4 — Parent web dashboard foundation (2 weeks)
- **Objective:** first real parent UI, used to drive every later phase.
- **Prerequisites:** P3.
- **Features:** auth screens, family/child management, **pairing screen (QR + code)**, device list with status, simple policy editor (daily limit, app block list from inventory placeholder), blocked-attempts list stub, notifications stub.
- **Tasks:** Vite + Tailwind scaffolding; `api-client` package; TanStack Query; routing; QR rendering (`qrcode` lib); form validation using shared Zod schemas; token handling (cookie refresh).
- **Acceptance:** register → add child → generate code → (device paired via API script) → see device → edit & publish policy → version increments.
- **Challenges:** cookie/CSRF flow for refresh; keep bundle small.

### Phase 5 — Android child application foundation (2–3 weeks)
- **Objective:** a real Android app that pairs, stores credentials, heartbeats, and fetches a policy.
- **Prerequisites:** P3 (pairing endpoints), P0 spikes.
- **Features:** Expo dev-build app; onboarding with **transparency/consent screen**; code entry/QR scan (`expo-camera` or manual-code-only for MVP); secure credential storage (Keystore-backed); Kotlin `ApiClient` (OkHttp) + `PolicyStore` (Room) + `SyncManager` (WorkManager) — **native from the start so sync survives JS death**; permission-guide screens (Usage Access, Overlay, Notifications, Battery optimisation, VPN later) using deep-links; status screen; PIN setup.
- **Tasks:** M5.1 Expo module scaffold + manifest config plugin; M5.2 pairing flow; M5.3 Kotlin networking + token refresh; M5.4 Room schema + signed-policy verification stub; M5.5 heartbeat worker; M5.6 permission detectors → capabilities report; M5.7 foreground service skeleton with notification.
- **Files:** `apps/child-mobile/app/*`, `modules/enforcement-android/android/src/main/java/.../{api,store,sync,perm,service}/*`, `plugins/withEnforcementManifest.ts`.
- **Acceptance:** device appears **ACTIVE** on dashboard with accurate capability states; heartbeat arrives every ~15 min with screen off; app survives swipe-away (service restarts) on test device(s); unpair/revoke works.
- **Challenges:** foreground-service type declaration; `Restricted settings`; OEM battery killers; Expo prebuild vs committed `android/` decision (ADR-004).

### Phase 6 — Native Android usage tracking (2 weeks)
- **Objective:** accurate, uploaded usage data.
- **Prerequisites:** P5, S-AND-1.
- **Features:** `UsageCollector` converting `UsageEvents` → closed sessions (handle screen-off, task switches, split-screen, duplicates); local usage counters per local day; installed-app inventory upload; outbox + batch uploader; ingest endpoint + tables + idempotency; aggregation job v1; dashboard "Today" chart.
- **Tasks:** M6.1 session builder with JVM tests (golden event sequences); M6.2 local counters (Room); M6.3 outbox + batch upload (gzip, backoff, jitter); M6.4 ingest API + validation + `IngestBatch`; M6.5 aggregation (pg-boss) + `UsageDailyAggregate`; M6.6 dashboard charts.
- **Acceptance:** device total for a day within ±2 % or ±2 min of Digital Wellbeing/`dumpsys` (choose larger tolerance, document known gaps); replaying batches creates no duplicates; late batch updates correct day; midnight-spanning session split correctly.
- **Challenges:** event edge cases per OEM/Android version; defining "screen time" (ADR-005).

### Phase 7 — Android application restrictions (2–3 weeks)
- **Objective:** local enforcement of app blocks, per-app/total limits, schedules.
- **Prerequisites:** P6 (usage counters), P5.
- **Features:** pure-Kotlin `EnforcementEngine` (spec §6.9) + golden vectors; foreground-app watcher (UsageEvents-driven + screen state; optional AccessibilityService strengthening); block screen/overlay; always-allowed apps; schedules incl. cross-midnight; temporary exceptions; time-tamper detection; blocked-attempt outbox; limit-reached → server → parent push; dashboard policy editor for these rules; parent "+30 min" button.
- **Tasks:** M7.1 engine + test vectors (TS reference + Kotlin); M7.2 foreground watcher + latency measurement; M7.3 block UI + "ask for more time" request flow (creates a notification for parent; no auto-grant); M7.4 schedules + exceptions; M7.5 tamper/clock detection; M7.6 notifications pipeline (FCM to parent via Expo push/FCM).
- **Acceptance:** §15.4 criteria for app blocking, limits, schedules, time tampering; engine golden vectors pass in TS and Kotlin; battery impact measured and recorded.
- **Challenges:** background activity start restrictions; double-counting when block screen itself is foreground (exclude own package); preventing bricking (never block settings dialer/emergency; PIN escape hatch for parent).

### Phase 8 — Android website filtering (2–3 weeks)
- **Objective:** domain/category blocking via local DNS VpnService.
- **Prerequisites:** P7 (engine), S-AND-4.
- **Features:** `DnsFilterVpnService` (UDP/53 intercept, forward allowed queries via protected socket to upstream; block via NXDOMAIN/sinkhole); domain matcher (trie/hash set; allow-list > deny > category); category list download + verification (sha256) + on-disk bloom/hash structure; blocked-domain events; VPN-state monitoring + parent alert; handling Private DNS/DoH bypass (detect Private DNS setting; block known DoH IPs/domains in the DNS path; document residual gaps); Tier-2 hook for always-on VPN.
- **Tasks:** M8.1 minimal VPN + pass-through; M8.2 DNS parse/answer; M8.3 matcher + lists; M8.4 events/log + dashboard; M8.5 bypass tests; M8.6 Play-policy disclosure screen.
- **Acceptance:** §15.4 website-blocking criteria; memory < 30 MB with 5 category lists loaded (target); no connectivity regression (YouTube/Maps/WhatsApp continue); IPv6 handled.
- **Challenges:** IPv6, DoH/DoT, other VPN apps (only one active VPN) ✅ NetGuard FAQ, captive portals, battery, Play VpnService policy. **Fallback if infeasible:** ship app-level blocking only and document "website blocking requires Device Owner mode / browser extension".

### Phase 9 — Policy synchronisation and offline enforcement (2–3 weeks)
- **Objective:** production-grade sync (§9).
- **Prerequisites:** P7 (+P8 optional), P3.
- **Features:** policy compiler (Android) + **JWS signing/verification**; `If-None-Match`; FCM wake-up (device + token refresh); `desired/applied` tracking + ack with per-capability results; rollback protection; `validUntil/softRefreshAfter`; offline `failMode`; emergency lock; parent WebSocket live status; drift detection + alerts; exception grants through versions.
- **Tasks:** M9.1 compiler + signer + key rotation (`kid`); M9.2 device verification + persistence; M9.3 FCM; M9.4 acks + dashboard sync status; M9.5 offline/chaos tests; M9.6 WS hub.
- **Acceptance:** §15.4 sync/offline/revoke criteria; tampered payload rejected; older version rejected; policy applied ≤ 30 s with FCM, ≤ 20 min without.
- **Challenges:** FCM high-priority quota behaviour; ensuring wake-up path works under Doze; key management.

### Phase 10 — Activity collection and analytics (2 weeks)
- **Objective:** trustworthy reports.
- **Prerequisites:** P6, P9.
- **Features:** categories via `AppCatalog` seed (curated ~300 popular apps + manual overrides + "Uncategorised"); category aggregates; website activity panel; weekly/monthly trends; blocked-attempt reports; notification rules (limit reached, permission lost, device stale); retention jobs; export/delete child data; partition-ready indexes.
- **Acceptance:** aggregation never double counts (browser + website panel separate); dashboards read only aggregates (query plans verified); retention job tested; data export produces a human-readable bundle.
- **Challenges:** app categorisation quality; timezone edges; data volume tuning.

### Phase 11 — Desktop browser extension (2–3 weeks)
- **Objective:** Chrome/Edge parity for website rules; Firefox build target.
- **Prerequisites:** P9 (sync protocol), P8 (domain model).
- **Features:** pairing (code), device token, policy fetch/ack, compiled DNR rules (dynamic + static category rulesets), schedules via `chrome.alarms`, blocked page, offline cache, optional (off-by-default) activity tracking with visible indicator, popup showing "managed by <family>", heartbeat; Firefox build with event-page background; enterprise-policy install guide.
- **Acceptance:** §15.4 extension criteria; works after service-worker eviction/browser restart; passes MV3 store validation locally; documented limitations (other browsers, incognito, admin removal).
- **Challenges:** DNR quotas; service-worker lifecycle; incognito consent; Firefox API differences.

### Phase 12 — iOS implementation (4–8+ weeks, gated by Mac + entitlement)
- **Objective:** maximum officially-permitted functionality (§4.C).
- **Prerequisites:** Mac, Apple Developer Program, **Family Controls distribution entitlement for all bundle IDs**, physical iPhone + Family Sharing child account, P9.
- **Tasks:** M12.1 spike: authorise `.child`, FamilyActivityPicker, apply shield; M12.2 **token portability spike** (parent device picks → encodes → child applies); M12.3 DeviceActivity schedules/thresholds + Monitor extension; M12.4 Shield configuration/action extensions; M12.5 iOS compiler (backend) + capability reporting (`APP_USAGE_REPORTING: UNSUPPORTED`); M12.6 App Group plumbing; M12.7 APNs; M12.8 TestFlight with **App Store–signed** build testing (reports of differences ✅).
- **Acceptance:** shield/schedule/threshold work without the app running; documented list of unsupported features visible in dashboard; Apple review submission prepared.
- **Challenges:** entitlement delay; extension memory limits 🟡; reported false positives on newer iOS builds ✅; no usage export; opaque tokens; `.individual` vs `.child` differences.

### Phase 13 — Security, reliability and product readiness (3–4 weeks)
- **Objective:** make it safe to put in strangers' hands.
- **Features:** 2FA (TOTP); device-bound keys (proof-of-possession) + optional Play Integrity/App Attest signals; cert-pinning decision; full IDOR/pen-test pass; privacy policy + child-facing notice; Play Data Safety/Accessibility/VPN declarations; Apple privacy labels; crash reporting (opt-in/PII-scrubbed); backups + restore drill; rate-limit review; observability; load test; incident runbook; legal review (COPPA/GDPR/DPDP) 🟡; beta feedback loop.
- **Acceptance:** all high/medium findings closed; restore drill passed; privacy docs published; store listings drafted; load test meets SLOs.

### 16.3 Rough calendar (solo, ~12 h/week)
P0–P4 ≈ 2.5–3.5 months → **demoable backend + dashboard**. P5–P9 ≈ 3.5–4.5 months → **demoable Android enforcement MVP**. P10–P11 ≈ 1.5–2 months. P12 depends on hardware/approval. P13 ≈ 1 month. **Total ≈ 9–13 months to a hardened Android+extension beta**, iOS in addition. Cut scope before extending the schedule: the **minimum impressive portfolio demo** is P0–P9 with app blocking + limits + schedule + sync + dashboard (≈ 6–8 months).

### 16.4 MVP vs future-enhancement summary

| Area | MVP | Later |
|---|---|---|
| Android | Standard mode, usage, app block/limit/schedule, DNS blocking | Device Owner mode, Accessibility-strengthened detection, per-OEM tuning |
| Web | DNS + domain lists | Safe search enforcement, category ML, URL-level |
| Policy | Single policy/child, exceptions | Presets, per-device overrides, rewards |
| Sync | FCM + pull + ack + signed | Device-bound keys, E2E-encrypted payloads |
| iOS | Shield + schedule + thresholds | Content filter ext (`.child`) 🟡 |
| Desktop | Browser extension | Native agent |
| Guardians | Owner only | Multi-guardian roles, audit UI |
| Reports | Daily/weekly | Monthly, email digests, export |

---

## 17. Documentation and Engineering Practices

### 17.1 Documents to maintain (in `docs/`, linked from README)

| File | Content | Owner/update trigger |
|---|---|---|
| `PROJECT_REQUIREMENTS.md` | FR-IDs, MVP scope, non-goals | Update when scope changes; PR must reference FR-IDs |
| `SYSTEM_ARCHITECTURE.md` | Diagrams (Mermaid), module boundaries, sync design | Any cross-module change |
| `DATABASE_SCHEMA.md` | ERD + table notes (generated ERD via `prisma-erd-generator` 🟡 optional) | Every migration PR updates it |
| `API_DOCUMENTATION.md` | Endpoint catalogue (generated from Zod/OpenAPI where possible) | CI check fails if OpenAPI drifts |
| `DEVELOPMENT_SETUP.md` | §13 distilled, tested on a fresh VM quarterly | Tooling changes |
| `IMPLEMENTATION_ROADMAP.md` | §16 with checkboxes and actual dates | End of each milestone |
| `SECURITY.md` | Threat model, disclosure policy, key rotation, RPO/RTO | Quarterly + after incidents |
| `CONTRIBUTING.md` | Branching, commits, PR rules, test commands | When process changes |
| `PRIVACY_AND_DATA.md` | Data inventory, retention, consent screens | Any new data field |
| `docs/adr/NNNN-title.md` | Architecture Decision Records | One per major decision |
| `docs/spikes/*.md` | Spike write-ups with device/OS evidence | Phase 0 and ad hoc |

**ADR template:** *Title · Status (proposed/accepted/superseded) · Context · Decision · Alternatives considered · Consequences · Date.* Seed list: ADR-001 modular monolith; 002 Expo+Kotlin boundary; 003 single child app; 004 prebuild vs committed `android/`; 005 screen-time definition; 006 DNS-via-VPN for Android web filtering; 007 no Redis in MVP (pg-boss); 008 policy signing (EdDSA/JWS); 009 typed activity tables; 010 retention defaults.
**Maintenance rule:** *a PR that changes behaviour documented in a doc must change the doc in the same PR* (checklist item in the PR template). Prefer generated docs (OpenAPI, ERD) to hand-written duplicates.

### 17.2 Git and review practices
- **Branching:** trunk-based with short-lived branches: `main` always deployable; `feat/…`, `fix/…`, `chore/…`; tags `vMAJOR.MINOR.PATCH` for releases; `release/*` only if you must patch an old store build.
- **Commits:** Conventional Commits (`feat(policy): add exception grants`), scope = module/app. Enforce with `commitlint` 🟡 or a simple hook.
- **PRs:** small (< 400 lines), description with *what/why/how tested*, link FR-IDs/ADRs, screenshots for UI, migration notes, checklist (tests, docs, security impact, privacy impact, backwards-compat of API/device protocol).
- **Review (even solo, self-review via PR):** checks — authorisation on every new route, `familyId` scoping, validation present, no secrets/PII in logs, idempotency for device writes, migration safety (backward-compatible; expand→migrate→contract), native code lifecycle/battery.
- **Backward compatibility rule:** devices in the field run old app versions for weeks. **Never** remove or change meaning of an API field/policy field in place; add new fields, bump `schemaVersion` only with a server that can compile both.
- **Config:** 12-factor env vars; per-environment `.env`; secrets in CI secret store; separate Firebase projects for dev/prod.
- **CI/CD:** GitHub Actions: PR → lint/typecheck/unit/integration; `main` → build API image + deploy to staging; tag → production deploy + store build artifacts (`bunx eas build --local` or Gradle `bundleRelease`). DB migrations run via `prisma migrate deploy` as a release step before app start.
- **Release management:** semantic versions; `minSupportedVersion` served by API; staged rollouts on Play (internal → closed → open); feature flags (simple `Family.flags` jsonb) for risky features; changelog from Conventional Commits; rollback = redeploy previous image (migrations must be backward compatible).

---

## 18. Cost Analysis

> Prices/limits below come from third-party comparisons I could read (dated Sep–Nov 2026) and vendor pages; **free tiers change often — re-check each vendor's pricing page before relying on one.**

### 18.1 Costs by stage

| Item | Development | Demo | Production |
|---|---|---|---|
| Hardware | Existing laptop + 1 Android phone (**plus a cheap spare phone for Device Owner tests**) | same | – |
| **Google Play Console** | – | – | USD 25 one-time 🟡 |
| **Apple Developer Program** | needed from Phase 0/12 for the entitlement and device builds | – | USD 99/yr 🟡 |
| Mac for iOS | needed at Phase 12 | – | – |
| Domain + TLS | – | optional (~USD 10/yr; or free subdomain) | required |
| Backend hosting | local | $0 options below | paid (~USD 5–50/mo at S2) |
| Postgres | local native | free tier or local | managed/own (~USD 6–25+/mo) |
| Push | FCM free; APNs free with Apple programme | same | same |
| Email | console/MailHog-style local | free tier SMTP | transactional provider |
| Monitoring | pino logs | UptimeRobot-style free checks | Sentry/Grafana paid/self-host |

### 18.2 Free / low-cost options and where they stop

| Need | Option | Free limits (as reported) | Becomes paid / breaks when |
|---|---|---|---|
| **Backend hosting** (long-running Node + WebSocket) | **Your Nobara machine + Cloudflare Tunnel** (`cloudflared`) 🟡 | Tunnel is free; compute is yours | Machine off = demo off; not for real users |
| | Render free web service | 1 service ~512 MB; **spins down after ~15 min idle with 30+ s cold start** ✅ | Cold starts break device sync and WS; paid instance (~USD 7/mo) |
| | Fly.io | **No free tier for new accounts** ✅ (card + pay-as-you-go) | Immediately |
| | Railway | Trial credit only ✅ | After credit |
| | Cloudflare Workers | ~100k req/day free ✅ | **Not a fit for Express + Prisma + `ws` long connections** (different runtime); would need a rewrite — don't |
| **Postgres** | **Neon** free | ~0.5 GB, ~191 compute-hours/mo, scale-to-zero with cold-start wake ✅ | Storage beyond 0.5 GB or constant uptime → paid (~USD 19/mo Launch ✅ reported) |
| | **Supabase** free | 500 MB, **pauses after ~1 week idle** ✅, 2 active projects | Auto-pause hurts always-on device sync; Pro USD 25/mo ✅ |
| | Local Postgres | free | Only for dev/demo on your machine |
| **Frontend hosting** | Cloudflare Pages / Vercel Hobby / Netlify | Static hosting generous/unlimited bandwidth on Pages ✅ | Hobby plans restrict commercial use — read terms |
| **Redis** | Not needed in MVP | – | Upstash free (~256 MB / 500k commands/mo, one source ✅) when you adopt Redis |
| **CI/CD** | GitHub Actions free minutes 🟡 | Limits apply (esp. macOS minutes cost multiples) | Private repos beyond quota; macOS builds |
| **Push to devices** | FCM free; APNs free | – | – |
| **Email** | Provider free tiers (e.g., ~100/day reported for Resend ✅ one source) | Daily caps | Volume growth |
| **Error tracking** | Sentry free (~5k errors/mo reported ✅) or self-host GlitchTip 🟡 | Caps | Volume |
| **Uptime** | UptimeRobot/Uptime Kuma (self-host) | – | – |
| **EAS Build (iOS from Linux)** | Expo free plan includes limited builds ✅ (Expo says free plan has headroom for dev builds) | Queue time/limits | Frequent iOS builds |
| **Domain-category data** | Open lists (check licences) | Free | Commercial use may require a commercial list (e.g., licensed category feeds) |

### 18.3 Recommended $0 demo stack
Laptop runs Postgres + API + worker (`bun run dev` or a built container) exposed with **Cloudflare Tunnel**; dashboard on **Cloudflare Pages** pointing at the tunnel hostname; FCM for push; local SMTP capture or a free transactional tier; Android phone connected over Wi-Fi to the tunnel hostname. **Caveat:** a laptop-hosted backend is fine for a recorded demo/interview, not for anyone depending on it for real supervision.

### 18.4 Honest statement about "free forever"
No free tier will carry a public parental-control service: always-on connectivity, backups, security updates and support create costs as soon as real families depend on it. Plan the **first paid step** at beta (a ~USD 5–15/mo VPS or small PaaS + managed Postgres), and budget Play/Apple fees, domain, email, and monitoring.

---

## 19. Risks, Assumptions and Unresolved Technical Decisions

### 19.1 Explicit assumptions
1. Initial users are your own family/testers who consent; public release comes later with legal review.
2. Test devices: at least one physical Android 12+ device you can dedicate; a second (spare) for Device Owner experiments.
3. Child devices have Google Play Services (FCM). Devices without it (some Huawei/de-Googled ROMs) will rely on polling (degraded latency).
4. Parents and children share a language/locale initially (English); i18n is planned in data model only.
5. Android 8+ (API 26+) minimum; API 29+ recommended for `ACTIVITY_RESUMED` events.

### 19.2 Technical limitations stated plainly
- Android Standard mode **can be bypassed** by a determined child (uninstall via safe mode/ADB, factory reset, second user profile, other VPN, clock tricks without detection on some OEMs). The product *detects and reports* rather than *guarantees*.
- DNS filtering does not see URL paths, HTTPS content, or in-app traffic using IP/DoH; it blocks by hostname.
- iOS gives no per-app usage export, no history, opaque tokens, extension memory constraints, and entitlement-gated distribution ✅.
- Browser extension covers only one browser profile; removable by anyone with browser admin rights unless enterprise-managed.
- Foreground-app detection granularity differs across OEMs; accuracy targets are validated per device.
- Play policy may reject or restrict Accessibility, VPN, and broad package visibility usage; the architecture keeps each as optional/degradable.

### 19.3 Risk register (top items)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Apple Family Controls distribution entitlement delayed/denied | High | iOS blocked | Request in Phase 0; ship Android first; clear use-case text |
| R2 | OEM battery managers kill enforcement | High | Core feature unreliable | OEM guidance in app, battery-opt exemption prompt, heartbeat-based staleness alerts, multi-device testing |
| R3 | Play Store rejection (Accessibility/VPN/QUERY_ALL_PACKAGES) | Medium | Distribution blocked | Optional Accessibility, in-app disclosures, `<queries>` launcher intent, prepare declaration videos, fallback sideload/F-Droid distribution for demo |
| R4 | Expo/RN upgrade churn (SDK cadence, New Architecture) | Medium | Maintenance cost | Pin SDK, upgrade per release cycle, keep native code in local modules, avoid third-party native libs where possible |
| R5 | VpnService conflicts (other VPNs, IPv6, DoH) | High | Web filtering gaps | Documented limitations, DoH mitigation list, Tier-2 always-on VPN |
| R6 | Dev machine memory/CPU limits | High | Slow builds | §13.9 budget; JVM tests; ABI restriction; consider free CI for heavy builds |
| R7 | Privacy/legal exposure (children's data) | Medium | Launch blocker | Data minimisation, consent UX, legal review, no analytics SDKs |
| R8 | Clock tampering / bypass of schedules | Medium | Enforcement gap | Server-offset time, change detection, alerts, optional DO time lock |
| R9 | Policy/schema drift across TS/Kotlin/Swift | Medium | Bugs | Golden vectors, generated types, schemaVersion discipline |
| R10 | Scope creep (location, messages, etc.) | Medium | Privacy + time | Explicit non-goals (§1.2); ADR required for new data categories |

### 19.4 Unresolved technical decisions (to be settled by spikes/ADRs)
1. **Precise "screen time" definition** (interactive foreground time vs. including media playback; per-device vs. per-child concurrency) — ADR-005.
2. **Foreground detection:** UsageEvents-only vs UsageEvents + AccessibilityService (latency vs Play policy risk) — decide after S-AND-2.
3. **Block UI mechanism:** overlay window vs transparent Activity vs Accessibility-global-action — S-AND-2.
4. **Expo prebuild-generated `android/` vs committed `android/`** — ADR-004.
5. **DNS filter implementation:** from-scratch minimal VpnService vs adapting Apache-2.0 RethinkDNS components — S-AND-4 + code review of licence/structure.
6. **Category data source & licence** for web categories; whether a server-side categorisation API is needed.
7. **iOS token portability** between parent and child devices (remote selection) — S-IOS spike; fallback = on-device configuration.
8. **iOS usage reporting alternative** (accept limitation vs. DeviceActivityReport-based on-device view for the child only).
9. **Device-bound credentials**: Android Keystore keys in MVP or Phase 13.
10. **Pairing confirmation UX** (parent confirm step vs trust-on-code).
11. **WebSocket vs SSE** for the parent live view (SSE is simpler through proxies; `ws` is fine too).
12. **Time source for trusted time** (server offset only vs. NTP via device) and behaviour offline for days.
13. **Hosting target** for demo (tunnel vs small VPS) and DB (local vs Neon).
14. **Multi-child device sharing** (one device used by two children) — out of MVP; model assumes 1 child/device.
15. **Product name/trademark** and bundle identifiers (bundle IDs are permanent for Apple entitlements — choose carefully before requesting).

---

## 20. References and Official Documentation

> Links are to primary documentation. Re-verify before relying on specific limits/versions (🟡 items above).

**Android**
- Android Developers — UsageStatsManager: https://developer.android.com/reference/android/app/usage/UsageStatsManager
- Device administration / Device Policy Controller overview: https://developer.android.com/work/dpc/build-dpc ; DevicePolicyManager reference: https://developer.android.com/reference/android/app/admin/DevicePolicyManager
- VpnService: https://developer.android.com/reference/android/net/VpnService
- AccessibilityService: https://developer.android.com/reference/android/accessibilityservice/AccessibilityService
- Foreground services (types, restrictions): https://developer.android.com/develop/background-work/services/fgs
- WorkManager: https://developer.android.com/topic/libraries/architecture/workmanager
- Doze & App Standby: https://developer.android.com/training/monitoring-device-state/doze-standby
- Package visibility: https://developer.android.com/training/package-visibility
- Android command-line tools / sdkmanager / adb: https://developer.android.com/tools
- Firebase Cloud Messaging (Android): https://firebase.google.com/docs/cloud-messaging/android/client
- Google Play policies (Accessibility API, VpnService, Families, permissions): https://support.google.com/googleplay/android-developer/topic/9858052

**Apple**
- Family Controls: https://developer.apple.com/documentation/familycontrols ✅
- Requesting the Family Controls entitlement / distribution request form: https://developer.apple.com/contact/request/family-controls-distribution ✅
- ManagedSettings: https://developer.apple.com/documentation/managedsettings
- DeviceActivity: https://developer.apple.com/documentation/deviceactivity
- ManagedSettingsUI: https://developer.apple.com/documentation/managedsettingsui
- Apple Developer Forums — Family Controls tag (practical limitations, entitlement reports): https://developer.apple.com/forums/tags/family-controls ✅
- App Review Guidelines (Kids / parental controls): https://developer.apple.com/app-store/review/guidelines/

**React Native / Expo**
- Expo docs (dev builds, prebuild, config plugins, Modules API): https://docs.expo.dev ; SDK changelogs: https://expo.dev/changelog (SDK 55: https://expo.dev/changelog/sdk-55 ✅; SDK 56 upgrade notes: https://expo.dev/blog/upgrading-to-sdk-56 ✅)
- Expo Modules API: https://docs.expo.dev/modules/overview/
- React Native docs: https://reactnative.dev/docs/getting-started ; New Architecture: https://reactnative.dev/architecture/landing-page

**Web extensions**
- Chrome Extensions (MV3, declarativeNetRequest, service workers, alarms): https://developer.chrome.com/docs/extensions
- MDN WebExtensions (Firefox, compatibility): https://developer.mozilla.org/docs/Mozilla/Add-ons/WebExtensions
- Microsoft Edge extensions: https://learn.microsoft.com/microsoft-edge/extensions-chromium/

**Backend / data**
- Express 5: https://expressjs.com ; Node.js: https://nodejs.org/docs ; Zod: https://zod.dev ; Pino: https://getpino.io ; jose: https://github.com/panva/jose ; pg-boss: https://github.com/timgit/pg-boss
- PostgreSQL (partitioning, indexes, RLS): https://www.postgresql.org/docs/current/
- Prisma docs (schema, migrations, config): https://www.prisma.io/docs
- OWASP ASVS / Cheat Sheets (Password Storage, JWT, REST security): https://cheatsheetseries.owasp.org
- RFC 9449 (DPoP) for proof-of-possession concept: https://www.rfc-editor.org/rfc/rfc9449

**Open-source projects reviewed (§12)**
- Open TimeLimit (GitLab): https://gitlab.com/timelimit.io/opentimelimit-android ✅ ; F-Droid request metadata showing GPL-3.0-only ✅: https://gitlab.com/fdroid/rfp/-/issues/867 ; TimeLimit privacy policy ✅: https://legal.timelimit.io/en/privacy
- timelimit-parent (derivative console): https://github.com/mpashka/timelimit-parent ✅
- RethinkDNS: https://github.com/celzero/rethink-app ✅ ; NetGuard: https://github.com/M66B/NetGuard ✅ ; Acutis Firewall (F-Droid): https://f-droid.org/en/packages/com.acutis.firewall/ ✅
- KidSafe: https://github.com/xMansour/kidSafe ✅ ; KidShield: https://github.com/Yousaf1204/KidShield ✅ ; Screen Time Calculator: https://github.com/rati-bar/Android-app ✅ ; Times-up (Flutter): https://github.com/JordyHers-org/Times-up-flutter ✅ ; YouTubeWhitelist: https://github.com/degipe/YouTubeWhitelist ✅

**Hosting/cost references used for §18** (third-party comparisons, re-verify on vendor pages): Neon pricing https://neon.com/pricing · Supabase pricing https://supabase.com/pricing · Render https://render.com/pricing · Fly.io https://fly.io/docs/about/pricing · Cloudflare Workers limits https://developers.cloudflare.com/workers/platform/limits/

---

### Appendix A — What I could not verify (summary)
Licence type, language and last-commit dates for most projects in §12 beyond those marked ✅; current Google Play minimum target API and the exact policy wording for Accessibility/VPN/QUERY_ALL_PACKAGES; Declarative Net Request current rule quotas; iOS extension memory limits (community-reported); the newest Expo SDK number as of today (SDK 56 confirmed; a vendor changelog hints SDK 57 exists); Prisma's current config syntax; India's DPDP Rules timeline/exemptions. Each is flagged 🟡 or "NOT VERIFIED" at point of use and each has a corresponding Phase 0 task or ADR to close it.

### Appendix B — First 10 commands to run tomorrow
```bash
sudo dnf install -y git java-17-openjdk-devel android-tools postgresql-server postgresql-contrib
curl -fsSL https://bun.sh/install | bash && curl -fsSL https://fnm.vercel.app/install | bash
# install cmdline-tools → sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
mkdir kidguard && cd kidguard && git init && mkdir -p apps packages docs infrastructure
bun create expo-app apps/child-mobile
cd apps/child-mobile && bunx expo install expo-dev-client
bunx expo prebuild --platform android
adb devices   # phone connected with USB debugging
bunx expo run:android --device
# then: start Phase 0 spikes S-AND-1 … S-AND-5
```
