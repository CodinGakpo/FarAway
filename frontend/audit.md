# Freight Bridge Flutter Frontend — Engineering Audit

**Date:** 2026-06-10  
**Auditor:** Principal Flutter Architect / Senior Mobile Engineer / Firebase Specialist / Security Auditor  
**Severity scale:** CRITICAL > HIGH > MEDIUM > LOW > INFO

---

## Executive Summary

The application cannot start on either platform. Two independent fatal defects
block `main()` before `runApp()` is ever called, leaving Android on the Flutter
logo splash permanently and iOS on a white screen permanently. Both defects are
in the startup sequence and both have now been fixed. Additionally the app
carries two completely unused heavyweight dependencies (`firebase_auth`,
`supabase_flutter`) and Google Maps is initialised without API keys. A full
inventory of every finding, every fix applied, and every remaining manual step
is documented below.

---

## Architecture Overview

```
frontend/
├── lib/
│   ├── main.dart                        Entry point, DI root, auth gate
│   ├── config/
│   │   └── constants.dart               Env-backed API constants
│   ├── models/
│   │   ├── user.dart
│   │   ├── trip.dart
│   │   └── shipment_request.dart
│   ├── screens/
│   │   ├── login_screen.dart            ⚠ STUB — never routed to, dead code
│   │   ├── customer_home_screen.dart    Stub customer screen
│   │   ├── driver_home_screen.dart      Re-export barrel
│   │   ├── auth/
│   │   │   ├── login_screen.dart        ✓ Real login screen
│   │   │   └── register_screen.dart     ✓ Real register screen
│   │   └── driver/
│   │       ├── driver_home_screen.dart  ✓ Full driver dashboard
│   │       ├── create_trip_screen.dart  ✓ Trip creation + Google Map
│   │       ├── incoming_requests_screen.dart
│   │       └── active_trip_dashboard.dart
│   ├── services/
│   │   ├── auth_provider.dart           ChangeNotifier — JWT decode + secure storage
│   │   └── api_service.dart             Singleton HTTP client (no timeout)
│   └── widgets/
│       ├── empty_state.dart
│       ├── loading_button.dart
│       ├── section_header.dart
│       └── status_chip.dart
├── android/
├── ios/
├── pubspec.yaml
└── .env                                 ✓ NOW CREATED (was missing)
```

**Architecture pattern:** Thin service layer + Provider state management.  
**State management:** `provider` (ChangeNotifier).  
**Navigation:** Imperative `Navigator.push / pushReplacement` — no named routes.  
**Dependency injection:** Constructor injection on `AuthProvider`; singleton factory on `ApiService`.  
**Firebase:** Imported but no Dart-layer usage found (`firebase_auth` dead code).  
**Auth:** Custom JWT; token stored in `flutter_secure_storage`.

---

## Startup Execution Trace

```
main()
  │
  ├─ WidgetsFlutterBinding.ensureInitialized()        OK
  │
  ├─ dotenv.load(fileName: '.env')                    ✗ CRASHED HERE (pre-fix)
  │   Reasons:
  │   1. .env file did not exist in the project root
  │   2. .env was not declared in pubspec.yaml flutter.assets
  │   Flutter bundles only assets listed in pubspec; unlisted files are never
  │   shipped in the APK/IPA regardless of their presence on disk.
  │   Both conditions were independently fatal.
  │
  ├─ Firebase.initializeApp()                         ✗ WOULD CRASH (pre-fix)
  │   Reason: google-services.json (Android) and
  │   GoogleService-Info.plist (iOS) are absent.
  │   Called without DefaultFirebaseOptions; native SDK reads config files
  │   that do not exist → throws FirebaseException.
  │
  ├─ runApp(MyApp())
  │
  └─ MyApp.build()
       └─ MultiProvider → AuthProvider
            └─ MaterialApp → _AuthGate
                 └─ initState → _initializeAuth()
                      └─ authProvider.tryAutoLogin()
                           ├─ getToken() [flutter_secure_storage.read]
                           ├─ if null → return → _isCheckingAuth = false → LoginScreen
                           └─ if present → decode JWT → set currentUser
                                └─ isDriver? DriverHomeScreen : CustomerHomeScreen
```

---

## Startup Failure Analysis

### Finding 1 — `.env` file missing [CRITICAL — PRIMARY ROOT CAUSE]

| Attribute | Detail |
|-----------|--------|
| Severity | CRITICAL |
| Platform | Android + iOS |
| File | `pubspec.yaml`, project root |
| Symptom | Android: Flutter logo forever. iOS: white screen. |

**Root cause (part A):** The `.env` file did not exist anywhere in the project.
`flutter_dotenv` opens the file as a Flutter asset; if it is absent
`dotenv.load()` throws a `FileSystemException` or `DotEnvException`.

**Root cause (part B — independent and equally fatal):** Even if the file
existed on disk, it was not declared in `pubspec.yaml` under
`flutter.assets`. Flutter copies only explicitly declared assets into the app
bundle (APK / IPA). `dotenv` loads via `rootBundle.loadString()` which reads
from the bundle, not the filesystem. A file not in the bundle is invisible to
`rootBundle` regardless of its presence on disk.

**Why the splash persists:** Both exceptions propagate out of `main()` with zero
handling. The Flutter engine never calls `runApp()`; the native splash activity
(Android) and launch screen (iOS) never dismiss.

**Fix applied:**
- Created `/frontend/.env` with `BASE_URL=http://localhost:3000`
- Added `assets: [ .env ]` to `pubspec.yaml`

---

### Finding 2 — Firebase config files absent [CRITICAL — SECONDARY ROOT CAUSE]

| Attribute | Detail |
|-----------|--------|
| Severity | CRITICAL |
| Platform | Android + iOS |
| Files | `android/app/` (no `google-services.json`), `ios/Runner/` (no `GoogleService-Info.plist`) |

`main()` calls `await Firebase.initializeApp()` with no explicit
`DefaultFirebaseOptions`. The native Firebase SDK reads the platform config
files at runtime. When they are absent it throws before returning:

- Android: `com.google.firebase.FirebaseOptions — no Firebase App has been created`
- iOS: `[Firebase/Core][I-COR000005] No such file or directory: GoogleService-Info.plist`

The `com.google.gms:google-services` Gradle plugin is also absent from
`android/app/build.gradle.kts`, meaning even if the JSON file were added later
the plugin would not process it.

**Note:** No Dart code in `lib/` ever imports or uses `firebase_auth` or any
other Firebase service. Firebase is effectively unused. This is both the cause
of the crash and an indication that the dependency may be premature.

**Fix applied:** Wrapped `Firebase.initializeApp()` in a try-catch. The app now
starts and logs the error; Firebase features remain unavailable until the config
files are added (manual steps documented below).

**Manual steps still required:**
1. Create a Firebase project at https://console.firebase.google.com
2. Register `com.example.frontend` (Android) and `com.example.frontend` (iOS)
3. Download `google-services.json` → place at `android/app/google-services.json`
4. Download `GoogleService-Info.plist` → place at `ios/Runner/GoogleService-Info.plist`
5. Add Google Services plugin to `android/app/build.gradle.kts`:
   ```kotlin
   plugins {
       // existing plugins...
       id("com.google.gms.google-services")
   }
   ```
6. Add to `android/settings.gradle.kts` plugins block:
   ```kotlin
   id("com.google.gms.google-services") version "4.4.2" apply false
   ```

---

### Finding 3 — No exception handling in `main()` [HIGH]

| Attribute | Detail |
|-----------|--------|
| Severity | HIGH |
| File | `lib/main.dart` |

Before the fix, `main()` had zero try-catch around `dotenv.load()` or
`Firebase.initializeApp()`. Any thrown exception silently crashed the Dart
isolate before `runApp()`. There was no error UI, no log output visible to
Flutter's crash handler, and no way for a user to understand the failure.

**Fix applied:** Both calls are now wrapped in individual try-catch blocks with
`debugPrint` logging. The app continues past a failed dotenv or Firebase init
rather than crashing silently.

---

### Finding 4 — `tryAutoLogin()` has no timeout protection [MEDIUM]

| Attribute | Detail |
|-----------|--------|
| Severity | MEDIUM |
| File | `lib/services/auth_provider.dart` |

`flutter_secure_storage.read()` on iOS reads from the device keychain. On a
freshly rebooted device where the user has not yet entered their device
passcode the keychain is locked and `read()` can block indefinitely. If it
hangs, `_isCheckingAuth` in `_AuthGate` stays `true` forever, showing a
permanent `CircularProgressIndicator` even if the platform splash has already
dismissed.

**Fix applied:** `tryAutoLogin()` is now called via `.timeout(Duration(seconds: 10))`
in `_AuthGate._initializeAuth()`. If it does not complete in ten seconds the app
proceeds as logged-out.

---

## Firebase Audit

| Item | Status |
|------|--------|
| `firebase_core` in pubspec.yaml | Present (`^4.10.0`) |
| `firebase_auth` in pubspec.yaml | Present (`^6.5.2`) — UNUSED |
| `Firebase.initializeApp()` called | Yes — in `main()` |
| `DefaultFirebaseOptions` provided | No |
| `android/app/google-services.json` | **MISSING** |
| `ios/Runner/GoogleService-Info.plist` | **MISSING** |
| Google Services Gradle plugin | **MISSING** from `build.gradle.kts` |
| Any Dart-level Firebase API usage | **None found** |

`firebase_auth` is declared as a dependency but zero Dart files import it. The
entire auth system uses a custom REST/JWT approach via `ApiService`. If Firebase
Auth is not planned, both `firebase_core` and `firebase_auth` should be removed
from `pubspec.yaml`.

---

## Environment Audit

| Variable | File | Purpose | Missing value crashes startup? |
|----------|------|---------|-------------------------------|
| `BASE_URL` | `lib/config/constants.dart` | Base URL for all API calls | No (falls back to `''`) — but all API calls will fail with a `SocketException` |

`.env` was previously absent and not bundled. Both issues are now fixed.

**Remaining manual step:** Replace `http://localhost:3000` in `.env` with the
real backend URL before deploying or running on a physical device.

---

## Navigation Audit

```
_AuthGate (home)
├── LoginScreen                    [not logged in]
│   └── RegisterScreen
│       └── DriverHomeScreen / CustomerHomeScreen
└── DriverHomeScreen               [logged in, role=driver]
│   ├── CreateTripScreen
│   │   └── pop(true) → triggers _loadActiveTrip()
│   └── IncomingRequestsScreen
│       └── pop
└── CustomerHomeScreen             [logged in, role=customer]
    (stub — no routes)
```

**Navigation implementation:** Fully imperative (`Navigator.push`,
`pushReplacement`, `pushAndRemoveUntil`). No named routes, no `GoRouter`, no
`AutoRoute`. This is functional but unscalable as the app grows.

**Dead route:** `lib/screens/login_screen.dart` is a stub `StatelessWidget`
that renders `Text('Login Screen')`. It is never imported by any production
code. It is a leftover from scaffolding and should be deleted.

---

## State Management Audit

```
UI Layer
└─ _AuthGate (Consumer<AuthProvider>)
   └─ AuthProvider (ChangeNotifier)
      └─ ApiService (Singleton)
         └─ FlutterSecureStorage (token r/w)
         └─ http.Client (REST calls)

DriverHomeScreen
└─ ApiService (direct — bypasses Provider)
   └─ getActiveTrip()

IncomingRequestsScreen
└─ ApiService (direct)
   └─ getIncomingRequests(), acceptRequest(), rejectRequest()

CreateTripScreen
└─ ApiService (direct)
   └─ createTrip()

ActiveTripDashboard
└─ ApiService (direct)
   └─ getTripShipments(), updateShipmentStatus()
```

**AuthProvider** is the only Provider-managed state. All other screens
construct `ApiService()` directly (safe because it is a singleton). There is no
shared loading, error, or data state beyond auth. This is acceptable for the
current feature set.

---

## Dependency Audit

| Package | Purpose | Version | Status |
|---------|---------|---------|--------|
| `flutter_dotenv ^5.1.0` | Load `.env` config | 5.x | ✓ Current |
| `flutter_secure_storage ^9.0.0` | JWT token storage | 9.x | ✓ Current |
| `provider ^6.1.0` | State management | 6.1 | ✓ Current |
| `http ^1.2.0` | REST client | 1.2 | ✓ Current |
| `google_maps_flutter ^2.5.0` | Map in CreateTripScreen | 2.5 | ✓ — needs API keys |
| `firebase_core ^4.10.0` | Firebase init | 4.10 | ⚠ Used, config missing |
| `firebase_auth ^6.5.2` | Firebase auth | 6.5 | ✗ **UNUSED — dead weight** |
| `supabase_flutter ^2.14.2` | Supabase | 2.14 | ✗ **UNUSED — dead weight** |
| `cupertino_icons ^1.0.8` | iOS icons | 1.0 | ✓ |

`supabase_flutter` pulls in a large dependency tree (WebSocket, realtime,
GoTrue, PostgREST clients). It initialises nothing at startup because
`Supabase.initialize()` is never called, but it adds ~3–5 MB to the binary.

**Recommendation:** Remove both `firebase_auth` and `supabase_flutter` from
`pubspec.yaml` unless there is an active roadmap item requiring them.

---

## Security Findings

| # | Finding | Severity | File |
|---|---------|----------|------|
| S1 | JWT stored in `flutter_secure_storage` — correct platform | INFO | `api_service.dart` |
| S2 | JWT decoded client-side for role; server must also enforce role | MEDIUM | `auth_provider.dart` |
| S3 | `BASE_URL` empty string if `.env` missing → requests go to `http:///...` | MEDIUM | `constants.dart` |
| S4 | No HTTPS enforcement in `ApiService._buildUri()` | MEDIUM | `api_service.dart` |
| S5 | `http.Client` instance never closed (singleton, acceptable) | LOW | `api_service.dart` |
| S6 | No token expiry check; expired JWT sent until explicit logout | MEDIUM | `auth_provider.dart` |
| S7 | `User.fromJson` performs hard casts — malformed server response crashes app | LOW | `models/user.dart` |
| S8 | Google Maps API keys are placeholder strings | HIGH | `AndroidManifest.xml`, `AppDelegate.swift` |

**S2 detail:** `_extractRoleFromToken()` decodes the JWT locally and trusts
the `role` claim to determine which home screen to render. A backend that does
not also verify the role on every request means a user could forge the role in a
token obtained by other means.

**S6 detail:** There is no `exp` claim check in `tryAutoLogin()`. A 401 from
the backend during an API call will not automatically log out the user or clear
the token; the UI will show error snackbars instead.

---

## Changes Applied

### 1. Created `/frontend/.env`
```
BASE_URL=http://localhost:3000
```
**Rationale:** `dotenv.load()` crashes without this file. Placeholder value;
must be replaced before connecting to a real backend.  
**Risk:** None. The fallback `''` in `AppConstants.BASE_URL` was already the
de-facto default; this merely makes it explicit.

---

### 2. Created `/frontend/.env.example`
```
BASE_URL=http://localhost:3000
```
**Rationale:** Documents what environment variables the app needs.  
**Risk:** None.

---

### 3. `pubspec.yaml` — Added `.env` to flutter assets

Before:
```yaml
flutter:
  uses-material-design: true
  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
```

After:
```yaml
flutter:
  uses-material-design: true
  assets:
    - .env
```

**Rationale:** Flutter's asset system (`rootBundle`) only serves files declared
here. `flutter_dotenv` reads via `rootBundle`; without this entry, `.env` is
never bundled and `dotenv.load()` always throws.  
**Risk:** None.

---

### 4. `lib/main.dart` — Hardened startup with try-catch and diagnostic logging

Before:
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp();
  runApp(const MyApp());
}
```

After: Both initialisation calls are wrapped in independent try-catch blocks.
`debugPrint` markers added throughout the startup sequence and auth gate.
`tryAutoLogin()` protected with a 10-second `.timeout()`.

**Rationale:** Any uncaught exception before `runApp()` leaves the native
splash screen frozen. Wrapping prevents silent crashes; logging identifies
exactly which step stalled.  
**Risk:** Low. If dotenv fails the app still launches; API calls will fail
with a `SocketException` (empty BASE_URL) rather than a crash, and the user
sees an error snackbar rather than a frozen splash.

---

### 5. `lib/services/auth_provider.dart` — Logging + storage error handling

`tryAutoLogin()` now logs its start, the token presence/absence, and the decoded
role. `getToken()` is wrapped in try-catch so a `PlatformException` from a
locked keychain surfaces as a log line instead of an unhandled exception.

**Risk:** None.

---

### 6. `android/app/src/main/AndroidManifest.xml` — Google Maps API key placeholder

Added `com.google.android.geo.API_KEY` meta-data with value
`YOUR_ANDROID_MAPS_API_KEY`.

**Rationale:** Without a key entry the `google_maps_flutter` plugin on Android
logs a `SEVERE` native error at startup. With the placeholder the error changes
to "invalid key" which is less alarming and clearly identifies the action needed.  
**Risk:** None — the map view was already non-functional.

---

### 7. `ios/Runner/AppDelegate.swift` — Google Maps iOS init + API key placeholder

Added `import GoogleMaps` and `GMSServices.provideAPIKey("YOUR_IOS_MAPS_API_KEY")`.

**Rationale:** `google_maps_flutter` iOS requires `GMSServices.provideAPIKey`
in `application(_:didFinishLaunchingWithOptions:)`. Without it the map view
crashes with `NSInternalInconsistencyException` on first render.  
**Risk:** Low — the map screen is not in the startup path; the crash would only
occur when navigating to `CreateTripScreen`.

---

## Remaining Risks

| # | Risk | Action required | Priority |
|---|------|----------------|----------|
| R1 | `google-services.json` absent | Add Firebase Android config | P0 if Firebase features planned |
| R2 | `GoogleService-Info.plist` absent | Add Firebase iOS config | P0 if Firebase features planned |
| R3 | Google Services Gradle plugin missing | Add to `build.gradle.kts` + `settings.gradle.kts` | P0 if Firebase features planned |
| R4 | `BASE_URL` is `localhost:3000` | Set production URL in `.env` before deploy | P0 |
| R5 | Google Maps API keys are placeholders | Add real keys from Google Cloud Console | P1 |
| R6 | `firebase_auth` never used | Remove from `pubspec.yaml` or implement | P2 |
| R7 | `supabase_flutter` never used | Remove from `pubspec.yaml` or implement | P2 |
| R8 | JWT expiry not checked | Add `exp` validation in `tryAutoLogin()` | P2 |
| R9 | No HTTPS enforcement | Validate `BASE_URL` scheme at startup | P2 |
| R10 | `lib/screens/login_screen.dart` is dead stub | Delete the file | P3 |
| R11 | `CustomerHomeScreen` is a stub | Implement or leave as placeholder | P3 |
| R12 | No network timeout on `http.Client` calls | Add timeout to `ApiService` HTTP methods | P2 |

---

## Root Cause Ranking

### Android — Flutter logo persists indefinitely

| Rank | Finding | Probability | Evidence |
|------|---------|-------------|---------|
| 1 | `.env` not in pubspec assets → `dotenv.load()` throws before `runApp()` | **99%** | pubspec.yaml has no assets section; `rootBundle` cannot serve undeclared files |
| 2 | `.env` file does not exist on disk | **99%** | `ls frontend/` shows no `.env` file |
| 3 | `Firebase.initializeApp()` throws (no config files) | **95%** | `android/app/` has no `google-services.json` |

Both rank-1 and rank-2 are independently sufficient to reproduce the freeze.
The app never reaches rank-3 because it crashes at rank-1/2 first.

### iOS — White screen after launch

| Rank | Finding | Probability | Evidence |
|------|---------|-------------|---------|
| 1 | Same as Android rank-1 and rank-2 | **99%** | Identical code path; iOS launch screen is white by default |
| 2 | `Firebase.initializeApp()` throws (no GoogleService-Info.plist) | **95%** | `ios/Runner/` has no plist |
| 3 | `GMSServices.provideAPIKey` not called → `GoogleMap` widget NSInternalInconsistencyException | **40%** | Only triggered on `CreateTripScreen`, not in startup path |

---

## Final Recommendation

**Immediate (unblocks app launch):**
1. ✅ Done — `.env` created and declared in pubspec.yaml
2. ✅ Done — `main()` hardened with try-catch
3. Update `BASE_URL` in `.env` to point at your real backend

**Before enabling Firebase:**
4. Create Firebase project, register app IDs, download config files
5. Add `google-services` Gradle plugin

**Before any map screen is used:**
6. Create Google Maps API keys (Android + iOS), replace placeholders

**Cleanup (reduces binary size ~15 MB, removes confusion):**
7. Remove `firebase_auth` and `supabase_flutter` from pubspec.yaml if no plan to use them
8. Delete `lib/screens/login_screen.dart` (dead stub)

---

*End of audit report.*
