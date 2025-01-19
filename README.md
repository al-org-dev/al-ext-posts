# Al-Ext-Posts

A Jekyll plugin that allows you to fetch and display external blog posts from RSS feeds and specific URLs in your Jekyll site.

## Installation

Add this line to your Jekyll site's Gemfile:

```ruby
gem 'al_ext_posts'
```

And then execute:

```bash
$ bundle install
```

## Usage

1. Add the plugin to your site's `_config.yml`:

```yaml
plugins:
  - al_ext_posts
```

2. Configure your external sources in `_config.yml`:

```yaml
external_sources:
  - name: "My Blog"
    rss_url: "https://myblog.com/feed.xml"
  - name: "Another Source"
    posts:
      - url: "https://example.com/post1"
        published_date: "2024-03-20"
      - url: "https://example.com/post2"
        published_date: "2024-03-21"
```

The plugin supports two types of sources:
- RSS feeds: Provide the `rss_url` parameter
- Direct URLs: Provide a list of `posts` with `url` and `published_date`

## Development

After checking out the repo, run `bundle install` to install dependencies.

## Contributing

Bug reports and pull requests are welcome on GitHub.