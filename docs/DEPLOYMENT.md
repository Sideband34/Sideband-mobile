# Building and releasing Sideband-mobile

Sideband-mobile is the Flutter payer app. **Testnet and synthetic data only.**

## Build

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --release
```

CI (`.github/workflows/ci.yml`, job `test`) runs format, analyze and test on every push and pull request. The release workflow (`.github/workflows/release.yml`, job `android-apk`) runs on a `v*` tag and
publishes `sideband-android.apk` and `sideband-android.apk.sha256`, so `https://github.com/Sideband34/Sideband-mobile/releases/latest/download/sideband-android.apk` is stable.

The APK is **debug-signed** unless the four repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` are set. A debug-signed APK is fine for trying the app and
is not suitable for a store listing.

## Environment boundaries

| Environment | What runs |
|---|---|
| Local and CI | Flutter tests with fakes, plus an end-to-end test against `../Sideband-gateway` when that checkout exists |
| Testnet | Real `top_up` through `SorobanChannelClient` (one run recorded below) |
| Production | Not available |

Key material never leaves the device secure store, and no secret belongs in the app bundle.

## Device and Android build status (2026-11-04)

- `flutter build apk --release`: **succeeds** on the owner's Windows machine (`app-release.apk`, 50.6 MB). It needed two
  Gradle settings (both committed): `kotlin.incremental=false` (the project and the pub cache were on different drives, which
  breaks Kotlin's incremental compiler) and `compileSdk` 36 for library plugins (`stellar_flutter_sdk` is compiled against
  Android 34 but its AndroidX dependencies need 35+). `flutter doctor` still reports Android licences as not accepted; the
  build worked anyway, but the owner should run `flutter doctor --android-licenses` themselves.
- **No device test was done.** The APK has not been installed on a phone, so no session has run on hardware.
- **BLE (`universal_ble`) is experimental**: unit-tested with fakes only; no two-device test was possible. It is not wired
  into discovery.
- The channel actions default to the labelled on-device simulation. `SorobanChannelClient` (real `top_up`, `close_start`,
  `refund` through Soroban RPC with the device key) exists and is tested against a fake chain; one real Testnet `top_up`
  ran through it (`test/live/soroban_live_test.dart`, skipped unless `SIDEBAND_LIVE_*` is set). It is not selected by the
  UI yet, and `close_start`/`refund` were not run live through the Dart client.
- The release workflow runs on Linux and was not exercised by this run.
