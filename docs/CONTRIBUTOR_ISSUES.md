# Contributor issues — Sideband-mobile

Scoped work for **Sideband-mobile**, taken from the gaps listed in the README status table. These are
candidates, not yet all opened on GitHub; a maintainer opens an issue (labels: `good first issue`,
`bug`, `documentation`, `stellar`, `blocked`) once its dependencies are ready. Each item names its
interface touchpoints, acceptance tests and non-goals. Size: S (< 1 day), M (1–3 days), L (> 3 days).

Rules: Testnet/synthetic only; no real keys or funds; tests for failure paths; one repository
boundary per issue. Cross-repo work is listed at the end and needs a linked PR in each repo.

## Open work

- [ ] **Keychain/keystore `SecureStore`.** Implement on `flutter_secure_storage`. *Acceptance:*
  ledger and history survive restart; corrupt data fails loudly (existing tests reused).
  *Size:* M.
- [ ] **Hardware-backed signer.** Replace the test-only `SeedSigner` with a key generated and held
  in secure storage. *Acceptance:* signatures still match the golden-vector format; no seed is
  ever logged. *Size:* M.
- [ ] **Discovery over the protocol BLE adapter.** *Blocked on:* protocol BLE transport.
  *Acceptance:* the Discover screen lists real nearby providers on two physical devices; the
  synthetic provider stays available behind a demo toggle. *Size:* L.
- [ ] **Channel funding and settlement status.** Show Testnet funding and observe settlement so a
  receipt can move to "Settled on Stellar" only on finality. *Size:* L. Label: `stellar`.
- [ ] **Accessibility pass.** Semantics labels, large-text layout and contrast checks for every
  screen. *Acceptance:* widget tests with `textScaleFactor` 2.0 and semantics finders.
  *Size:* S. `good first issue`.
- [ ] **First tagged release.** Push `v0.1.0` to run `release.yml`, verify the APK installs on an
  emulator, and document the result. *Size:* S.

## Cross-repository

- [ ] **Integration lockfile.** A file in each repo pinning the tested sibling tags/SHAs, checked in
  CI. *Acceptance:* CI fails when a pinned sibling fixture differs. *Size:* M.
- [ ] **Testnet end-to-end demo.** Fund → offline session → settle on Testnet with recorded
  transaction hashes, driven from a clean checkout. *Blocked on:* channels Testnet deploy, gateway
  Soroban wiring. *Size:* L.
- [ ] **Physical-device compatibility harness.** Two-phone BLE/Wi-Fi run with a published matrix.
  *Blocked on:* protocol transport adapters. *Size:* L.
