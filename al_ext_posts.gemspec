Gem::Specification.new do |spec|
  spec.name          = "al_ext_posts"
  spec.version       = "0.1.0"
  spec.authors       = ["al-org"]
  spec.email         = ["dev@al-org.dev"]
  spec.summary       = "Import external posts from RSS feeds and URLs"
  spec.description   = "Jekyll plugin extracted from al-folio that imports external posts from RSS feeds or explicit URLs, with support for default tags and categories per source."
  spec.homepage      = "https://github.com/al-org-dev/al-ext-posts"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage
  }

  spec.files         = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 3.9", "< 5.0"
  spec.add_dependency "feedjira", ">= 3.2", "< 5.0"
  spec.add_dependency "httparty", ">= 0.18", "< 1.0"
  spec.add_dependency "nokogiri", ">= 1.13", "< 2.0"

  spec.add_development_dependency "bundler", ">= 2.0", "< 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
