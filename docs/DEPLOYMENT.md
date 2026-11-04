# Sideband — Environment, Deployment and Recovery

## Environment boundaries
- Local: deterministic Docker Compose services, Stellar local network/Testnet, synthetic users/fixtures.
- Staging: separate database, bucket, API credentials, signing identities, Testnet assets/contracts, observability.
- Production: requires security audit, real issuer/provider agreements and relevant jurisdictional legal/compliance review. Not included in preimplementation scaffold.

## Suggested variables (non-secret examples only)
```dotenv
APP_ENV=development
STELLAR_NETWORK=testnet
STELLAR_RPC_URL=https://soroban-testnet.stellar.org
HORIZON_URL=https://horizon-testnet.stellar.org
DATABASE_URL=postgresql://localhost:5432/sideband
REDIS_URL=redis://localhost:6379
API_BASE_URL=http://localhost:3001
CHAIN_START_LEDGER=0
LOG_LEVEL=info
```
- Credentials to sign on-chain go into a secure secret manager or hardware-backed user wallet, never into a public mobile/web bundle.
- Signed store badge links are configured after actual publication; no fabricated App Store or Google Play app URLs.

## CI & GitHub setup
- GitHub Actions per repo: formatting/lint, schema checks, unit tests, dependency scanning; chain/devices smoke tests where supported.
- Branch protection and PR review recommended.
- Release tag points to tested sibling versions in an integration lockfile.
- All paths use offline/synthetic test fixtures, not real user financial records.

## Failure recovery
- Rebuild indexers from ledger cursor; compare DB projection vs chain truth.
- Restore DB backups after verifying transaction-intent reconciliation.
- Never republish user transactions solely because a client request timed out.
- Test signing-key rotation, dependency outages, stale quotes, malicious user input, insufficient balances and duplicate delivery.
- External reference infrastructure may change; check upstream project versions and licenses at build time.

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
