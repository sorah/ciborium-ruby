# frozen_string_literal: true
# rbs_inline: enabled

require "rbconfig"

# Precompiled gems carry one extension per Ruby minor under lib/ciborium/<X.Y>/.
fat = File.expand_path("#{RUBY_VERSION[/\A\d+\.\d+/]}/ciborium_native", __dir__.to_s)
if File.exist?("#{fat}.#{RbConfig::CONFIG.fetch("DLEXT")}")
  require fat
else
  require_relative "ciborium_native"
end

module Ciborium
  module Native
    # Called by the encoder for text in an encoding other than UTF-8 or US-ASCII.
    #
    #: (String string) -> String
    def self.transcode(string)
      string.encode(Encoding::UTF_8)
    rescue EncodingError
      raise EncodeError, "cannot transcode a #{string.encoding} string to UTF-8"
    end
  end
end
