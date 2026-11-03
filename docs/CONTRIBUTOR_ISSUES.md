# Contributor issues — Sideband-mobile

Scoped work for **Sideband-mobile**, taken from the gaps listed in the README status table. These are
candidates, not yet all opened on GitHub; a maintainer opens an issue (labels: `good first issue`,
`bug`, `documentation`, `stellar`, `blocked`) once its dependencies are ready. Each item names its
interface touchpoints, acceptance tests and non-goals. Size: S (< 1 day), M (1–3 days), L (> 3 days).

Rules: Testnet/synthetic only; no real keys or funds; tests for failure paths; one repository
boundary per issue. Cross-repo work is listed at the end and needs a linked PR in each repo.

## Open work

- [ ] **Soroban `ChannelClient`.** Replace the labelled `SimulatedChannelClient` with one that
  submits `top_up`, `close_start` and `refund` (e.g. via `stellar_flutter_sdk`) on Testnet.
  *Acceptance:* the Channel tab shows real ledger results; a timeout is shown as "checking", never
  as done. *Size:* L. Label: `stellar`.
- [ ] **Wire `BleTransport` into discovery.** The adapter exists and is unit-tested with a fake
  GATT peer but is untested on hardware. *Acceptance:* the Discover screen lists a real nearby
  provider on two physical devices; the synthetic provider stays behind a demo toggle; permission
  denials are handled. *Size:* L.
- [ ] **Settlement observation.** Move a receipt to "Settled on Stellar" only on finality from
  Testnet. *Size:* M. Label: `stellar`.
- [ ] **Accessibility pass.** *Acceptance:* widget tests with text scale 2.0 and semantics
  finders for every screen, including the Channel tab. *Size:* S. `good first issue`.
- [ ] **First tagged release.** Push `v0.1.0` to run `release.yml`, check that
  `releases/latest/download/sideband-android.apk` serves it, install on an emulator and document
  the result. *Size:* S.

## Cross-repository

- [ ] **Integration lockfile.** A file in each repo pinning the tested sibling tags/SHAs, checked in
  CI. *Acceptance:* CI fails when a pinned sibling fixture differs. *Size:* M.
- [ ] **Testnet end-to-end demo.** Fund → offline session (two sessions on one channel) → settle on
  Testnet with recorded transaction hashes, driven from a clean checkout. *Blocked on:* running
  `scripts/deploy-testnet.sh` in Sideband-channels, gateway Soroban wiring. *Size:* L.
- [ ] **Physical-device compatibility harness.** Two-phone BLE run of the mobile `BleTransport`
  with a published matrix. *Acceptance:* a frame exchange of 10+ vouchers recorded per device
  pair; no row marked supported without a run. *Size:* L.
