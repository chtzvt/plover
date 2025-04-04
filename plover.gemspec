# frozen_string_literal: true

require_relative "lib/plover"

Gem::Specification.new do |spec|
  spec.name = "plover"
  spec.version = Plover::VERSION
  spec.authors = ["Charlton Trezevant"]
  spec.email = ["ct@ctis.me"]

  spec.summary = "Plover is a tiny, embeddable Ruby build system."
  spec.description = "Plover is a tiny, embeddable Ruby build system."
  spec.homepage = "https://github.com/chtzvt/plover"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/chtzvt/plover"
  spec.metadata["changelog_uri"] = "https://github.com/chtzvt/plover/releases"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.add_dependency "logger"

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
