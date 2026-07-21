# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"

gem "pry"
gem "simplecov"

group :test do
  # Instrumentations are soft dependencies (see the gemspec). net_http is the
  # only one that installs here, since Net::HTTP is stdlib; pg contributes its
  # option schema alone. Keep redis absent: setup_sdk_spec asserts the
  # missing-gem boot error against it.
  gem "opentelemetry-instrumentation-net_http"
  gem "opentelemetry-instrumentation-pg"
end

# Local checkouts while the gems are developed inside common/gems/.
# Switch to `github: "verse-rb/..."` once published.
gem "verse-core", github: "verse-rb/verse-core", branch: "master"
gem "verse-schema", "~> 1.2"
