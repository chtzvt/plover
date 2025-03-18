require_relative "../../lib/plover"
require "fileutils"

class PloverGemBuilder < Plover::Builder
  common_include_none

  expect_flags(
    :gem_version,
    :rubygems_release_token,
    :github_release_token
  )

  phase(:setup) do
    set_publish_keys
    install_dependencies
  end

  phase(:before_build) do
    validate_version
    standardize
    spec
  end

  phase(:build) do
    build_plover
  end

  phase(:after_build) do
    push_gem
  end

  def set_publish_keys
    log :info, "Configuring credentials..."
    home_gem_dir = File.expand_path("~/.gem")
    FileUtils.mkdir_p(home_gem_dir)

    credentials = <<~EOF
      ---
      :github: Bearer #{flag(:github_release_token)}
      :rubygems: #{flag(:rubygems_release_token)}
    EOF

    File.write(File.join(home_gem_dir, "credentials"), credentials)
    system("chmod 0600 #{File.join(home_gem_dir, "credentials")}")
  end

  def install_dependencies
    log :info, "Installing dependencies..."
    system("bundle install")
  end

  def validate_version
    log :info, "Checking Plover::VERSION..."
    fail_build("Invalid Plover::VERSION") unless flag(:gem_version) == Plover::VERSION
  end

  def standardize
    log :info, "Running Standard..."
    fail_build("Standardrb returned errors") unless system("bundle exec rake standard")
  end

  def spec
    log :info, "Running RSpec..."
    fail_build("RSpec returned errors") unless system("bundle exec rake spec")
  end

  def build_plover
    log :info, "Building Plover..."
    fail_build("Building Plover failed.") unless system("bundle exec rake build")

    gem_path = Dir.glob("pkg/plover-#{flag(:gem_version)}.gem").map { |f| File.expand_path(f) }.first

    fail_build("No gem was produced by the build step") unless gem_path

    push_artifact(:gem, gem_path)
  end

  def push_gem
    log :info, "Publishing Gem..."
    fail_build("Pushing Plover to RubyGems failed.") unless system("gem push #{esc_artifact(:build, :gem)} --key rubygems")
    fail_build("Pushing Plover to GitHub Packages failed.") unless system("gem push #{esc_artifact(:build, :gem)} --key github --host 'https://rubygems.pkg.github.com/chtzvt'")
  end
end

PloverGemBuilder.new.run
