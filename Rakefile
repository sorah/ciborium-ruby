# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"

GEMSPEC = Bundler.load_gemspec("ciborium.gemspec")

# No gemspec: precompiled gems are assembled by rakelib/native.rake.
Rake::ExtensionTask.new("ciborium_native") do |ext|
  ext.ext_dir = "ext/ciborium"
  ext.lib_dir = "lib/ciborium"
  ext.source_pattern = "{Cargo.toml,Cargo.lock,build.rs,src/**/*.rs}"
  # Platforms without a native CI runner are cross-compiled inside rb-sys-dock
  # images (see .github/workflows/native.yml).
  ext.cross_compile = true
  ext.cross_platform = %w[x86_64-linux-musl aarch64-linux-musl arm-linux-gnueabihf]
end

RSpec::Core::RakeTask.new(:spec)
task spec: :compile

namespace :spec do
  desc "Run the cbor gem's specs against Ciborium::Compat, with default and with all extensions"
  task upstream: :compile do
    ["default", "all"].each do |mode|
      sh(
        {"CIBORIUM_UPSTREAM_EXTENSIONS" => mode}, "rspec", "--options", "spec/upstream/.rspec", "-I", "spec/upstream",
        "--default-path", "spec/upstream", "spec/upstream"
      )
    end
  end
end

desc "Regenerate inline RBS signatures under sig/generated"
task :rbs do
  sh "rbs-inline --output=sig/generated lib"
  sh "rbs -r time -r uri -I sig/generated -I sig/manual -I sig-stub validate"
end

desc "Type check lib against the RBS signatures"
task steep: :rbs do
  sh "steep check"
end

task default: [:spec, "spec:upstream", :steep]
