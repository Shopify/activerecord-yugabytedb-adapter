# frozen_string_literal: true

require_relative "lib/version"

Gem::Specification.new do |spec|
  spec.name = "activerecord-yugabytedb-adapter"
  spec.version = ActiveRecord::YUGABYTE_DB_ADAPTER_VERSION
  spec.authors = ["YugabyteDB Development Team"]
  spec.email = ["info@yugabyte.com"]

  spec.summary = "YugabyteDB adapter for ActiveRecord."
  spec.description = "YugabyteDB adapter for ActiveRecord."
  spec.homepage = "https://docs.yugabyte.com/preview/drivers-orms/ruby/activerecord/"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/yugabyte/activerecord-yugabytedb-adapter"
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "activerecord", ">= 7.1.3.4"
  spec.add_dependency "yugabytedb-ysql", "~> 0.3"


  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
