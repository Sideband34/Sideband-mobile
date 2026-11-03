# Changelog

All notable changes to Sideband-mobile. Pre-release; Testnet/synthetic only.

## [Unreleased]

### Added
- Several sessions per channel (protocol v2 baseline); receipts show the session's own amount and
  the channel cumulative; `BaselineGap` / `provider_baseline_ahead` instead of silently paying.
- Payer crash resume: a session journal in secure storage; on restart the app re-attaches and
  re-sends a voucher that was signed but not delivered, or records the session as interrupted.
- Channel tab: status, top-up, close-start (dispute window) and refund, against a clearly
  labelled on-device simulation (no transactions sent).
- `FlutterSecureStore` (keychain / keystore) and `StoredKeySigner` (device-generated ed25519 key),
  tested through the plugin's platform channel; the app uses them for the ledger, journal and
  signer.
- `AtomicFileStore` for durable receipt history.
- `BleTransport` (+ `UniversalBleGattLink` on `universal_ble`) and `LanTransport` behind the
  protocol `Transport`; unit-tested with fakes, **untested on hardware**, not wired in.
- Android BLE / INTERNET permissions, iOS Bluetooth and local-network usage strings.

### Changed
- Release workflow publishes a normal (latest) release with a fixed `sideband-android.apk`
  (+ `.sha256`), so `releases/latest/download/sideband-android.apk` is stable.
- Refund wording reflects close-start + dispute window.

## [0.1.0]
- Payer domain, voucher signing against golden vectors, session runner, synthetic provider,
  HTTP link, app shell.
