# frozen_string_literal: true

require "json"
require "rubygems/package"

# Crates compiled into the extension, whose licenses a precompiled gem carries under licenses/.
# Proc-macro and build-time crates leave nothing in the binary. Kept in sync with NOTICE.md.
COMPILED_CRATES = %w[cfg-if ciborium-io ciborium-ll half magnus rb-sys zerocopy].freeze

# Ruby minors a precompiled gem carries; lib/ciborium/native.rb picks the matching directory at
# require time.
NATIVE_RUBY_MINORS = %w[3.3 3.4 4.0].freeze

namespace :gem do
  desc "Build a precompiled gem for PLATFORM from lib/ciborium/<X.Y>/ extensions"
  task :native, [:platform] do |_, args|
    platform = args.fetch(:platform) { abort "usage: rake 'gem:native[x86_64-linux-gnu]'" }
    binaries = NATIVE_RUBY_MINORS.flat_map do |minor|
      Dir["lib/ciborium/#{minor}/ciborium_native.{so,bundle}"]
    end
    missing = NATIVE_RUBY_MINORS.reject { |minor| binaries.any? { |b| b.include?("/#{minor}/") } }
    abort "missing extensions for Ruby #{missing.join(", ")}" unless missing.empty?

    licenses = bundle_crate_licenses

    spec = GEMSPEC.dup
    spec.platform = Gem::Platform.new(platform)
    spec.files = spec.files.reject { |f| f.start_with?("ext/") } + binaries + licenses
    spec.extensions = []
    spec.dependencies.delete_if { |dependency| dependency.name == "rb_sys" }
    # Newer Ruby minors have no binary here and fall back to the source gem.
    last = NATIVE_RUBY_MINORS.last.split(".").map(&:to_i)
    spec.required_ruby_version = [">= #{NATIVE_RUBY_MINORS.first}", "< #{last[0]}.#{last[1] + 1}.dev"]

    mkdir_p "pkg"
    path = Gem::Package.build(spec)
    mv path, "pkg/#{path}"
    puts "built pkg/#{path}"
  end
end

# Precompiled gems drop ext/, and with it any route to the crates' sources, so their license texts
# travel under licenses/ instead.
def bundle_crate_licenses
  metadata = JSON.parse(IO.popen(["cargo", "metadata", "--format-version", "1", "--manifest-path", "ext/ciborium/Cargo.toml"], &:read))
  packages = metadata.fetch("packages").select { |package| COMPILED_CRATES.include?(package.fetch("name")) }
  missing = COMPILED_CRATES - packages.map { |package| package.fetch("name") }
  abort "crates not found in cargo metadata: #{missing.join(", ")}" unless missing.empty?

  rm_rf "licenses"
  mkdir_p "licenses"
  packages.sort_by { |package| package.fetch("name") }.flat_map do |package|
    dir = File.dirname(package.fetch("manifest_path"))
    Dir[File.join(dir, "{LICENSE,COPYING,NOTICE}*")].sort.map do |source|
      target = "licenses/#{package.fetch("name")}-#{File.basename(source)}"
      cp source, target
      target
    end
  end
end

# bundler's release task pushes only the source gem; precompiled gems staged in pkg/ by the
# release workflow are pushed alongside it.
Rake::Task["release:rubygem_push"].enhance do
  Dir["pkg/#{GEMSPEC.name}-#{GEMSPEC.version}-*.gem"].sort.each do |gem|
    sh "gem", "push", gem
  end
end
