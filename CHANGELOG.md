# Changelog

## Unreleased

- Initial release: a CBOR encoder and decoder backed by a Rust extension, where tags carry meaning only through allowlisted extensions.
- Built-in extensions for bignums, Time, URI and Regexp.
- `profile: :ctap2` for the CTAP2 canonical CBOR encoding form that WebAuthn uses.
- `Ciborium::Compat` and `ciborium/replace`, a stand-in for the cbor gem's interface.
- RBS signatures under `sig/`.
