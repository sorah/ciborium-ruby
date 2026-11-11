# Notices

## Test fixtures

`spec/fixtures/webauthn/` holds attestation objects taken from the test suite of
[webauthn-ruby](https://github.com/cedarcode/webauthn-ruby) (`spec/support/seeds.rb` at v3.5.0),
which is available under the MIT License.

`spec/upstream/` holds the specs of [cbor-ruby](https://github.com/cabo/cbor-ruby) (the cbor gem,
`spec/` at commit 89e94f3b059deb58478eab51996f764fcc6ecd82), copied unmodified except for
`spec_helper.rb`, which is replaced. cbor-ruby is available under the Apache License 2.0, a copy
of which is in `spec/upstream/LICENSE.txt`.
