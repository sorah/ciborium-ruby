# frozen_string_literal: true

# Declares the bundle for a downstream project checked out under tmp/downstream, together with this
# ciborium, for running its specs against Ciborium::Compat. Its cbor dependency still resolves to
# the cbor gem, as in an application that depends on both.
module DownstreamSuite
  # Release and lint tooling the specs do not load. cose-ruby's bundler requirement also excludes
  # the Bundler that ships with Ruby 4.0.
  SKIPPED = ["appraisal", "bundler", "rake", "rubocop", "rubocop-performance", "rubocop-rake", "rubocop-rspec"].freeze

  def self.declare(dsl, project)
    relative = "../../tmp/downstream/#{project}"
    spec = Bundler.load_gemspec(Dir[File.join(File.expand_path(relative, __dir__), "*.gemspec")].fetch(0))

    dsl.source("https://rubygems.org")
    dsl.gem(spec.name, path: relative)
    dsl.gem("ciborium", path: "../..")
    # A bundled gem since Ruby 3.4, which cose-ruby 1.3.1's specs require without declaring it.
    dsl.gem("base64")
    spec.development_dependencies.each do |dependency|
      next if SKIPPED.include?(dependency.name) || dependency.name == "base64"

      dsl.gem(dependency.name, *dependency.requirement.as_list)
    end
  end
end
