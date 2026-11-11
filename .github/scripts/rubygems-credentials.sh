#!/usr/bin/env bash
# Trusted publishing token exchange that names the owner of a new gem, which
# rubygems/configure-rubygems-credentials cannot pass yet.
# Usage: RUBYGEMS_OWNER=<user id> rubygems-credentials.sh
set -euo pipefail

: "${RUBYGEMS_OWNER:?}"

jwt="$(
  curl -fsS -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=rubygems.org" | jq -r .value
)"
echo "::add-mask::${jwt}"

key="$(
  jq -n --arg jwt "${jwt}" --arg owner "${RUBYGEMS_OWNER}" '{jwt: $jwt, owner: $owner}' |
    curl -fsS --fail-with-body -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data-binary @- https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token |
    jq -r .rubygems_api_key
)"
if [[ -z "${key}" || "${key}" == null ]]; then
  echo "::error::RubyGems.org returned no API key"
  exit 1
fi
echo "::add-mask::${key}"

for name in GEM_HOST_API_KEY BUNDLE_GEM__PUSH_KEY RUBYGEMS_API_KEY; do
  echo "${name}=${key}" >> "${GITHUB_ENV}"
done
mkdir -p ~/.gem
install -m 600 /dev/null ~/.gem/credentials
printf -- '---\n:rubygems_api_key: %s\n' "${key}" > ~/.gem/credentials
