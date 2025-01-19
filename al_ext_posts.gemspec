Gem::Specification.new do |spec|
  spec.name          = "al_ext_posts"
  spec.version       = "0.1.0"
  spec.authors       = ["al-org"]
  spec.email         = ["dev@al-org.com"]
  spec.summary       = "al-folio plugin for fetching external posts from RSS feeds and URLs"
  spec.description   = "al-folio plugin that allows you to fetch and display external blog posts from RSS feeds and specific URLs in your al-folio site"
  spec.homepage      = "https://github.com/al-org-dev/al-ext-posts"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 3.0"
  spec.add_dependency "feedjira"
  spec.add_dependency "httparty"
  spec.add_dependency "nokogiri"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
