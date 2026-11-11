# frozen_string_literal: true

target :lib do
  signature "sig/generated", "sig/manual", "sig-stub"
  check "lib"

  # Loaded only by the time and uri extensions.
  library "time", "uri"
end
