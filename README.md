<img src="./brand/icon.svg" alt="Sideband logo" width="144" />

# sideband-mobile

> Sideband — Nearby services. Metered value. Stellar settlement.

**Status: M0/M1 payer domain layer implemented and tested; no device features (see Status below).** This repo is one of **exactly four meaningful independent codebases** in the Sideband Stellar-native project. It is not a placeholder created merely to increase Drips Wave submissions.

## Owns
Nearby service discovery UX, local sessions, payer/provider modes, secure signing, spending limits, usage history and receipts

## Why it is separate
It has a distinct runtime/toolchain, external interface, tests, release cadence and maintainership boundary. Its siblings depend on its delivered interface, but implementation responsibilities must not be duplicated.

## Sibling repositories
- `sideband-protocol` — BLE/local-Wi-Fi discovery, pairing, authenticated session frames, transport retries, metering message schema, backpressure and session IDs
- `sideband-gateway` — Local service hosting, provider authentication, usage meter, anti-replay voucher validation, metered-demo service, settlement preparation, product marketing web
- `sideband-channels` — Stellar channel deployment/adapters, prefunding, domain-separated cumulative commitments, close/refund, on-chain settlement and contract tests

## Architecture and development context
Start with:
- `AGENTS.md` — coding agent rules;
- `docs/PRD.md` — product purpose and MVP;
- `docs/SRD.md` — user/system requirements, APIs and state;
- `docs/ARCHITECTURE.md` — four-repository responsibilities, data and execution paths;
- `docs/TECHNICAL_BUILD.md` — recommended bootstrap, testing, phases;
- `docs/SECURITY.md` — security/trust boundaries;
- `docs/BRAND.md` — approved flat logo and flexible UI direction;
- `docs/ROADMAP.md` — milestone acceptance gates.

## Technical target
Flutter mobile. The actual product implementation starts at milestone M0; no real-money transactions or claims exist in this scaffold.

## Minimal integration contract
Always test the dependency path stated in ARCHITECTURE.md. Every new public endpoint/ABI/package message must be versioned and covered by consumer fixtures. See `docs/SRD.md` and `docs/TECHNICAL_BUILD.md`.

## Drips Wave
Stellar is essential: An online setup transaction deposits a supported Stellar asset into a Soroban one-way payment channel bound to a provider and payer commitment key. Approval/eligibility for Wave depends on substantive open-source implementation and organizer review, not repo count.


## Official project identity

The project uses the **approved flat SVG logo** in [`brand/icon.svg`](./brand/icon.svg), with an editable transparent vector mark in [`brand/mark.svg`](./brand/mark.svg). The [512 px GitHub organization avatar](./brand/org-avatar.png) is in the same directory. This logo is shared by all four project repositories. UI design remains intentionally flexible.


## Status: payer domain layer (v0.1.0)

**Implemented and tested** (`flutter test`, 31 tests; `flutter analyze` clean; `dart format` clean)

- `lib/domain/voucher.dart`: cumulative voucher creation (ed25519 via `package:cryptography`), byte-compatible with `sideband-commit-v2` (the upstream one-way-channel commitment XDR). Dart-computed preimages, commitments and **signatures equal the TypeScript golden vectors** from `sideband-channels`.
- `lib/domain/strkey.dart`: minimal `G...`/`C...` strkey codec, checked against the same vectors.
- `lib/domain/manifest.dart`: verifies the provider-signed manifest from `sideband-gateway` (stale, not-yet-valid, wrong network, untrusted provider, tamper).
- `lib/domain/payer_session.dart`: payer side of a session on top of `sideband_protocol`'s `SessionMachine`: offer validation against policy and the funded channel (provider, network, expiry), spend cap = min(user limit, offer cap, deposit), monotonic signing, refusal to sign past the budget, stop on provider close/error.
- `lib/domain/signed_ledger.dart`: high-water mark of signed amounts, advanced before signing; prevents rollback or re-signing after a restart (in-memory implementation only).
- `lib/domain/receipt.dart` + `lib/features/session/session_view.dart`: receipts whose wording is "committed (not settled)" until a confirmed state; widget tests assert nothing else says settled.
- Cross-repo parity: `test/fixtures/session-transcript.json` (from `sideband-gateway`) is decoded with `sideband_protocol`, and the Dart payer reproduces the gateway's accepted voucher byte for byte.

**NOT implemented / unverified**

- No BLE or local Wi-Fi discovery or transport (needs `nearby`/platform plugins and two physical phones). **Nothing has been run on a device or emulator**; Android/iOS folders are the unmodified `flutter create` templates and were never built.
- No secure keystore/keychain signer (only the test-only `SeedSigner`), no durable ledger, no stellar wallet/channel funding or settlement integration, no usage history persistence.
- The app shell shows one clearly labeled synthetic receipt only. State management (Riverpod) and routing (go_router) from the build guide are not adopted yet.
- Voucher/manifest layouts are Sideband test formats, not audited.

## Quick start

```
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

`sideband_protocol` is a git dependency on the `claude/drips-wave-maintainer-projects-iwucl5` branch. Fixtures under `test/fixtures/` are copied from `sideband-channels/fixtures/voucher-vectors.json` and `sideband-gateway/fixtures/session-transcript.json`; refresh them when those formats change.

## Siblings and compatibility

| Repo | Contract |
|---|---|
| `sideband-protocol` v0.1.0 | frames, `SessionMachine`, `Amount` |
| `sideband-channels` v0.1.0 | voucher byte layout (golden vectors) |
| `sideband-gateway` v0.1.0 | manifest + frame transcript fixture |
