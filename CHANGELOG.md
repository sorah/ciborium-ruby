# Changelog

## Unreleased

- Decode every NaN to `Float::NAN`. Repeated NaN map keys are now duplicate keys, instead of costing time quadratic in their number.
- Fix decoding when GC compaction runs mid-decode, such as under `GC.auto_compact` or inside an extension, which could raise a spurious duplicate key error or crash.

## 0.1.0 (2026-11-11)

- Initial release: a CBOR encoder and decoder backed by a Rust extension, where tags carry meaning only through allowlisted extensions.
- Built-in extensions for bignums, Time, URI and Regexp.
- `profile: :ctap2` for the CTAP2 canonical CBOR encoding form that WebAuthn uses.
- `Ciborium::Compat` and `ciborium/replace`, a stand-in for the cbor gem's interface.
- RBS signatures under `sig/`.
