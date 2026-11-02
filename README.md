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


## Status: payer domain, session runner and app shell (v0.1.0)

**Implemented and tested** (`flutter test`, 56 tests; `flutter analyze` and `dart format` clean)

- Domain (`lib/domain`): `sideband-commit-v2` voucher signing (the upstream one-way-channel Commitment XDR, hand-encoded; **Dart signatures equal the TypeScript golden vectors**), strkey codec, voucher signature verification, manifest verification (stale, network, tamper), `PayerSession` (provider/channel binding, spend cap = min(user limit, offer cap, deposit), monotonic signing, pay-on-402 path), honest receipts.
- Integrations (`lib/integrations`): `ProviderLink`/`Discovery` transport interfaces; `LoopbackProvider` (in-memory SYNTHETIC provider mirroring gateway rules); `HttpProviderLink` for the real gateway; `SessionRunner`; `SecureStore` abstraction with `StoreBackedSignedLedger` (serialized writes, fails loudly on corrupt data) and `HistoryRepository` (a confirmed receipt is never downgraded).
- App (`lib/app`, `lib/features`): Riverpod providers and a go_router shell with Discover, Session, Limit, History and Receipt screens driven by the loopback provider and the bundled gateway fixture. A persistent banner states pre-release/Testnet/synthetic.
- Cross-repo end-to-end (`test/e2e/gateway_e2e_test.dart`): spawns the real TypeScript gateway (test channel adapter, loopback only) and runs the Dart payer against it over HTTP: the gateway verifies a Dart-signed voucher, enforces channel reuse refusal, session/admin auth, and settlement preparation stays `SUBMITTED` (synthetic, never confirmed). Auto-skips when `../Sideband-gateway` (with `npm ci`) and `../Sideband-channels/dist` are absent; set `SIDEBAND_GATEWAY_DIR` to override.

**NOT implemented / unverified**

- No BLE or local Wi-Fi discovery/transport; no device or emulator run; Android/iOS folders are untouched `flutter create` templates, never built.
- No keychain/keystore: the only signer is the test-only `SeedSigner` (public test seed), and `SecureStore` has only a volatile in-memory implementation, so the app loses its ledger and history on restart. A flutter_secure_storage adapter is the next step and is not written.
- Payer-side session resume after a crash is not implemented; a channel that already carries signed commitments is refused for new sessions by design (cumulative amounts are per channel).
- No Stellar wallet/channel funding or settlement/confirmation in the app; receipts stay "committed" because nothing observes the chain.
- The demo clock is frozen at the fixture time so the fixture manifest verifies.
- CI does not run the e2e test (it skips without the gateway checkout).

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
| `sideband-channels` v0.1.0 | voucher bytes (`sideband-commit-v2` golden vectors) |
| `sideband-gateway` v0.1.0 | manifest + frame transcript fixture |
