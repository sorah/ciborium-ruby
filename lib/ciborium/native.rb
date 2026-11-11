# frozen_string_literal: true
# rbs_inline: enabled

# Precompiled gems carry one extension per Ruby minor under lib/ciborium/<X.Y>/.
fat = File.expand_path("#{RUBY_VERSION[/\A\d+\.\d+/]}/ciborium_native", __dir__.to_s)
if File.exist?("#{fat}.#{RbConfig::CONFIG.fetch("DLEXT")}")
  require fat
else
  require_relative "ciborium_native"
end
