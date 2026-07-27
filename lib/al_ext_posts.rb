require 'feedjira'
require 'httparty'
require 'jekyll'
require 'nokogiri'
require 'time'
require 'uri'

module AlExtPosts
  class ExternalPostsGenerator < Jekyll::Generator
    safe true
    priority :high

    # Extensions dropped from a URL segment before it is turned into a title,
    # so `.../my-post.html` reads as "My Post" rather than "My Post Html".
    PAGE_EXTENSIONS = %w[html htm xhtml shtml php asp aspx jsp cfm md markdown txt].freeze

    # Last-resort title for a URL with neither a usable path nor a host.
    FALLBACK_TITLE = 'External post'.freeze

    def generate(site)
      if site.config['external_sources'] != nil
        site.config['external_sources'].each do |src|
          puts "Fetching external posts from #{src['name']}:"
          if src['rss_url']
            fetch_from_rss(site, src)
          elsif src['posts']
            fetch_from_urls(site, src)
          end
        end
      end
    end

    def fetch_from_rss(site, src)
      xml = HTTParty.get(src['rss_url']).body
      return if xml.nil?
      begin
        feed = Feedjira.parse(xml)
      rescue StandardError => e
        puts "Error parsing RSS feed from #{src['rss_url']} - #{e.message}"
        return
      end
      process_entries(site, src, feed.entries)
    end

    def process_entries(site, src, entries)
      entries.each do |e|
        puts "...fetching #{e.url}"
        create_document(site, src['name'], e.url, {
          title: e.title,
          content: e.content,
          summary: e.summary,
          published: e.published
        }, metadata_for_post(src, e))
      end
    end

    def create_document(site, source_name, url, content, src = {})
      # The slug is still derived from the raw title so existing post URLs keep
      # their source-name fallback; only the published title is filled in.
      slug = build_slug(source_name, url, content[:title])
      title = resolve_title(content[:title], url)

      path = site.in_source_dir("_posts/#{slug}.md")
      doc = Jekyll::Document.new(
        path, { :site => site, :collection => site.collections['posts'] }
      )
      doc.data['external_source'] = source_name
      doc.data['title'] = title
      doc.data['feed_content'] = content[:content]
      doc.data['description'] = content[:summary]
      doc.data['date'] = content[:published]
      doc.data['redirect'] = url

      # Apply default categories and tags from source configuration
      if src['categories'] && src['categories'].is_a?(Array) && !src['categories'].empty?
        doc.data['categories'] = src['categories']
      end
      if src['tags'] && src['tags'].is_a?(Array) && !src['tags'].empty?
        doc.data['tags'] = src['tags']
      end

      doc.content = content[:content]
      site.collections['posts'].docs << doc
    end

    # Build a filesystem-safe post slug from the title, falling back to the
    # source name + last URL segment when the title is missing, blank, or made
    # up entirely of non-word characters. Guards against a nil title (e.g. an
    # RSS entry or fetched page with no <title>), which previously raised a
    # NoMethodError and aborted the whole build.
    def build_slug(source_name, url, title)
      return fallback_slug(source_name, url) unless title.to_s.match?(/\w/)

      slug = slugify(title)
      slug.empty? ? fallback_slug(source_name, url) : slug
    end

    # Fallback slug built from the source name and the last URL segment. Only
    # computed on the fallback path so the common (titled) case does no extra
    # string work.
    def fallback_slug(source_name, url)
      "#{slugify(source_name)}-#{url.split('/').last}"
    end

    # Drop every character that is not a word character, space, or hyphen in a
    # single pass, then translate the remaining spaces to hyphens. Equivalent to
    # the previous `gsub(' ', '-').gsub(/[^\w-]/, '')` pair, but avoids the
    # intermediate string and the second regexp scan.
    def slugify(value)
      value.to_s.downcase.strip.gsub(/[^\w -]/, '').tr(' ', '-')
    end

    # Title to publish for an ingested item. Fetches degrade in ways that leave
    # no title at all (an unreachable host, a page without <title>, an RSS item
    # with a blank one), and publishing that empty string produced a blank but
    # clickable row in the blog index plus a stream of Jekyll "Empty `slug`
    # generated" warnings. The source is listed in _config.yml by the user, so
    # the entry is kept: derive a readable title from the URL and warn that the
    # fetch degraded.
    def resolve_title(title, url)
      return title if title.to_s.match?(/[[:word:]]/)

      derived = title_from_url(url)
      Jekyll.logger.warn('ExternalPosts:', "No title found for #{url} - using #{derived.inspect} derived from the URL.")
      derived
    end

    # Turn the last meaningful path segment of a URL into a human-readable
    # title: "https://blog.google/technology/ai/gemini-update-2024/" becomes
    # "Gemini Update 2024". Trailing slashes, query strings and fragments are
    # ignored, percent-escapes are decoded, and a page extension is dropped.
    # Segments carrying no letters on their own (ids, /2024/05/ date parts) are
    # skipped in favour of an earlier one, and a URL left with no wordy segment
    # at all - a bare domain, an all-numeric path - falls back to its host.
    # Never raises and never returns an empty string.
    def title_from_url(url)
      segments = url_path_segments(url)
      segments[-1] = strip_page_extension(segments[-1]) unless segments.empty?

      title = humanize_segment(segments.reverse.find { |segment| segment.match?(/[[:alpha:]]/) })
      return title unless title.empty?

      host = url_host(url)
      host.empty? ? FALLBACK_TITLE : host
    end

    # Path segments of a URL, percent-decoded and stripped of blanks. Falls
    # back to trimming the query/fragment by hand for inputs URI cannot parse.
    def url_path_segments(url)
      path = begin
        URI.parse(url.to_s).path.to_s
      rescue URI::Error
        url.to_s.scrub('').split('#', 2).first.to_s.split('?', 2).first.to_s
      end

      path.split('/').map { |segment| decode_url_segment(segment) }.reject { |segment| segment.strip.empty? }
    end

    # Host of a URL, without a leading "www.". Empty when there is none.
    def url_host(url)
      host = begin
        URI.parse(url.to_s).host
      rescue URI::Error
        nil
      end

      host.to_s.sub(/\Awww\./i, '')
    end

    # Percent-decode a single URL segment, keeping the raw text whenever the
    # escapes are malformed or decode to invalid bytes. Scrubbed either way so
    # the callers below can match against it without raising.
    def decode_url_segment(segment)
      decoded = URI.decode_www_form_component(segment)
      (decoded.valid_encoding? ? decoded : segment).scrub('')
    rescue ArgumentError
      segment.scrub('')
    end

    # Drop a trailing web-page extension, keeping the segment untouched when
    # the extension is unknown (a version number, say) or is all there is.
    def strip_page_extension(segment)
      extension = File.extname(segment)
      return segment unless PAGE_EXTENSIONS.include?(extension.delete_prefix('.').downcase)

      stripped = segment.chomp(extension)
      stripped.empty? ? segment : stripped
    end

    # Split a URL segment on its separators and capitalize each word, leaving
    # words that are already cased alone: "google-gemini-io-2024" becomes
    # "Google Gemini Io 2024".
    def humanize_segment(segment)
      segment.to_s.gsub(/[^[:alnum:]]+/, ' ').split.map { |word| word.sub(/\A[[:lower:]]/, &:upcase) }.join(' ')
    end

    def fetch_from_urls(site, src)
      src['posts'].each do |post|
        puts "...fetching #{post['url']}"
        content = fetch_content_from_url(post['url'])
        content[:published] = parse_published_date(post['published_date'])
        create_document(site, src['name'], post['url'], content, metadata_for_post(src, post))
      end
    end

    def metadata_for_post(src, post)
      metadata = src.dup
      %w[categories tags].each do |key|
        value = metadata_value(post, key)
        metadata[key] = value if value && !(value.respond_to?(:empty?) && value.empty?)
      end
      metadata
    end

    def metadata_value(post, key)
      if post.respond_to?(:key?)
        post[key] || post[key.to_sym]
      elsif post.respond_to?(key)
        post.public_send(key)
      end
    end

    def parse_published_date(published_date)
      case published_date
      when String
        Time.parse(published_date).utc
      when Date
        published_date.to_time.utc
      else
        raise "Invalid date format for #{published_date}"
      end
    end

    def fetch_content_from_url(url)
      html = HTTParty.get(url).body
      parsed_html = Nokogiri::HTML(html)

      title = parsed_html.at('head title')&.text&.strip || ''

      description = parsed_html.at('head meta[name="description"]')&.attr('content')
      description ||= parsed_html.at('head meta[name="og:description"]')&.attr('content')
      description ||= parsed_html.at('head meta[property="og:description"]')&.attr('content')

      body_content = parsed_html.search('p').map { |e| e.text }
      body_content = body_content.join() || ''

      {
        title: title,
        content: body_content,
        summary: description
        # Note: The published date is now added in the fetch_from_urls method.
      }
    end
  end
end
