require 'minitest/autorun'
require 'ostruct'
require 'date'
require 'time'
require 'tmpdir'

require_relative '../lib/al_ext_posts'

class AlExtPostsGeneratorTest < Minitest::Test
  class CaptureGenerator < AlExtPosts::ExternalPostsGenerator
    attr_reader :calls

    # Jekyll instantiates every Generator subclass with the site config when a
    # real site is built, so accept and ignore it.
    def initialize(*)
      @calls = []
    end

    def create_document(site, source_name, url, content, src = {})
      @calls << {
        site: site,
        source_name: source_name,
        url: url,
        content: content,
        src: src
      }
    end
  end

  def setup
    @generator = AlExtPosts::ExternalPostsGenerator.new
  end

  def with_singleton_method_stub(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end

  # Collect the messages the generator sends to Jekyll's logger instead of
  # printing them, so the degraded-fetch warning can be asserted on.
  def capture_jekyll_warnings
    warnings = []
    with_singleton_method_stub(Jekyll.logger, :warn, ->(topic, message = nil) { warnings << [topic, message].compact.join(' ') }) do
      yield
    end
    warnings
  end

  # A throwaway Jekyll site, enough for create_document to build real documents.
  def with_site
    Dir.mktmpdir do |dir|
      config = Jekyll.configuration('source' => dir, 'destination' => File.join(dir, '_site'), 'quiet' => true)
      yield Jekyll::Site.new(config)
    end
  end

  def test_parse_published_date_accepts_string_and_date
    from_string = @generator.parse_published_date('2025-01-10')
    from_date = @generator.parse_published_date(Date.new(2025, 1, 10))

    assert_equal Time.parse('2025-01-10').utc, from_string
    assert_equal Date.new(2025, 1, 10).to_time.utc, from_date
  end

  def test_parse_published_date_rejects_invalid_type
    assert_raises(RuntimeError) { @generator.parse_published_date(123) }
  end

  def test_process_entries_passes_expected_content_to_create_document
    generator = CaptureGenerator.new
    entries = [
      OpenStruct.new(
        url: 'https://example.com/a-post',
        title: 'A post',
        content: '<p>Body</p>',
        summary: 'Summary',
        published: Time.utc(2024, 1, 2),
        categories: ['rss'],
        tags: ['feed']
      )
    ]
    src = { 'name' => 'Example Source', 'categories' => ['external'], 'tags' => ['imported'] }

    generator.process_entries(:site, src, entries)

    assert_equal 1, generator.calls.length
    call = generator.calls.first
    assert_equal 'Example Source', call[:source_name]
    assert_equal 'https://example.com/a-post', call[:url]
    assert_equal 'A post', call[:content][:title]
    assert_equal 'Summary', call[:content][:summary]
    assert_equal ['rss'], call[:src]['categories']
    assert_equal ['feed'], call[:src]['tags']
  end

  def test_process_entries_keeps_source_metadata_when_entry_has_none
    generator = CaptureGenerator.new
    entries = [
      OpenStruct.new(
        url: 'https://example.com/a-post',
        title: 'A post',
        content: '<p>Body</p>',
        summary: 'Summary',
        published: Time.utc(2024, 1, 2)
      )
    ]
    src = { 'name' => 'Example Source', 'categories' => ['external'], 'tags' => ['imported'] }

    generator.process_entries(:site, src, entries)

    call = generator.calls.first
    assert_equal ['external'], call[:src]['categories']
    assert_equal ['imported'], call[:src]['tags']
  end

  def test_fetch_content_from_url_extracts_title_description_and_body
    html = <<~HTML
      <html>
        <head>
          <title>Example title</title>
          <meta name="description" content="A short description">
        </head>
        <body>
          <p>First paragraph.</p>
          <p>Second paragraph.</p>
        </body>
      </html>
    HTML

    with_singleton_method_stub(HTTParty, :get, ->(*) { OpenStruct.new(body: html) }) do
      content = @generator.fetch_content_from_url('https://example.com/post')

      assert_equal 'Example title', content[:title]
      assert_equal 'A short description', content[:summary]
      assert_equal 'First paragraph.Second paragraph.', content[:content]
    end
  end

  def test_fetch_from_rss_handles_parse_errors
    src = { 'rss_url' => 'https://example.com/feed.xml' }

    with_singleton_method_stub(HTTParty, :get, ->(*) { OpenStruct.new(body: '<rss></rss>') }) do
      with_singleton_method_stub(Feedjira, :parse, ->(*) { raise StandardError, 'bad feed' }) do
        assert_nil @generator.fetch_from_rss(:site, src)
      end
    end
  end

  def test_fetch_content_from_url_handles_missing_title
    html = <<~HTML
      <html>
        <body>
          <p>Only a body, no head/title.</p>
        </body>
      </html>
    HTML

    with_singleton_method_stub(HTTParty, :get, ->(*) { OpenStruct.new(body: html) }) do
      content = @generator.fetch_content_from_url('https://example.com/no-title')

      assert_equal '', content[:title]
      assert_equal 'Only a body, no head/title.', content[:content]
    end
  end

  def test_build_slug_from_normal_title
    slug = @generator.build_slug('Example Source', 'https://example.com/a-post', 'Hello, World!')

    assert_equal 'hello-world', slug
  end

  def test_build_slug_falls_back_when_title_is_nil
    slug = @generator.build_slug('Example Source', 'https://example.com/some-post', nil)

    assert_equal 'example-source-some-post', slug
  end

  def test_build_slug_falls_back_when_title_has_no_word_characters
    slug = @generator.build_slug('Example Source', 'https://example.com/entry-42', '!!!')

    assert_equal 'example-source-entry-42', slug
  end

  def test_build_slug_drops_punctuation_and_keeps_hyphens
    slug = @generator.build_slug('Example Source', 'https://example.com/x', 'Weekly Update: Part-2 (final)!')

    assert_equal 'weekly-update-part-2-final', slug
  end

  def test_build_slug_sanitizes_source_name_in_fallback
    slug = @generator.build_slug("Maruan's Blog!", 'https://example.com/posts/entry-7', nil)

    assert_equal 'maruans-blog-entry-7', slug
  end

  def test_build_slug_falls_back_for_title_without_ascii_word_characters
    slug = @generator.build_slug('Example Source', 'https://example.com/post-9', '你好世界')

    assert_equal 'example-source-post-9', slug
  end

  def test_slugify_matches_previous_two_pass_behavior
    [
      'Hello, World!',
      '  Leading and trailing  ',
      'Tabs\tand\nnewlines',
      'already-hyphenated',
      'Ünïcödé tïtlé',
      'multiple   spaces',
      'Example Source'
    ].each do |value|
      legacy = value.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')

      assert_equal legacy, @generator.slugify(value), "slugify diverged for #{value.inspect}"
    end
  end

  def test_resolve_title_keeps_a_usable_title
    title = nil
    warnings = capture_jekyll_warnings { title = @generator.resolve_title('A real title', 'https://example.com/posts/my-post') }

    assert_equal 'A real title', title
    assert_empty warnings
  end

  def test_resolve_title_keeps_a_title_without_ascii_word_characters
    title = nil
    capture_jekyll_warnings { title = @generator.resolve_title('你好世界', 'https://example.com/posts/my-post') }

    assert_equal '你好世界', title
  end

  def test_resolve_title_derives_from_url_when_title_is_missing
    title = nil
    warnings = capture_jekyll_warnings { title = @generator.resolve_title(nil, 'https://example.com/posts/my-post') }

    assert_equal 'My Post', title
    assert_equal 1, warnings.length
    assert_includes warnings.first, 'https://example.com/posts/my-post'
  end

  def test_resolve_title_derives_from_url_when_title_is_blank
    title = nil
    warnings = capture_jekyll_warnings { title = @generator.resolve_title("  \n\t ", 'https://example.com/posts/my-post') }

    assert_equal 'My Post', title
    assert_equal 1, warnings.length
  end

  def test_resolve_title_derives_from_url_when_title_has_only_non_word_characters
    title = nil
    warnings = capture_jekyll_warnings { title = @generator.resolve_title('!!! ***', 'https://example.com/posts/my-post') }

    assert_equal 'My Post', title
    assert_equal 1, warnings.length
  end

  def test_title_from_url_handles_url_shapes
    {
      # the entry that shipped an empty title in a real build
      'https://blog.google/technology/ai/google-gemini-update-flash-ai-assistant-io-2024/' => 'Google Gemini Update Flash Ai Assistant Io 2024',
      'https://example.com/posts/my-post' => 'My Post',
      'https://example.com/posts/my-post/' => 'My Post', # trailing slash
      'https://example.com/posts/my-post.html' => 'My Post', # page extension
      'https://example.com/posts/my-post.html?utm_source=x#intro' => 'My Post', # query and fragment
      'https://example.com/posts/hello%20world%21' => 'Hello World', # percent-encoding
      'https://example.com/posts/my_post_title' => 'My Post Title',
      'https://example.com/archive/2024/05/deep-dive/' => 'Deep Dive', # numeric segments skipped
      'https://example.com/posts/12345' => 'Posts', # purely numeric last segment
      'https://example.com/posts/---/' => 'Posts', # last segment has no words
      'https://example.com/post.v2' => 'Post V2', # unknown extension is kept
      'https://blog.google' => 'blog.google', # domain only
      'https://blog.google/' => 'blog.google',
      'https://www.example.com/' => 'example.com',
      'https://example.com/////' => 'example.com', # empty segments only
      'https://example.com/2024/05/12/' => 'example.com' # no segment carries words
    }.each do |url, expected|
      assert_equal expected, @generator.title_from_url(url), "title_from_url diverged for #{url.inspect}"
    end
  end

  def test_title_from_url_never_raises_or_returns_empty
    [
      nil,
      '',
      '/',
      'not a url at all',
      'https://example.com/bad%zz-escape',
      "https://example.com/posts/\xC3(invalid-bytes)",
      'https://example.com/%E4%BD%A0%E5%A5%BD'
    ].each do |url|
      title = @generator.title_from_url(url)

      refute_empty title.to_s, "title_from_url returned an empty title for #{url.inspect}"
    end
  end

  def test_create_document_publishes_a_derived_title_when_the_fetch_yielded_none
    url = 'https://blog.google/technology/ai/google-gemini-update-flash-ai-assistant-io-2024/'
    content = { title: '', content: 'Body', summary: nil, published: Time.utc(2024, 5, 14) }

    with_site do |site|
      capture_jekyll_warnings { @generator.create_document(site, 'Google Blog', url, content) }
      doc = site.collections['posts'].docs.last

      assert_equal 'Google Gemini Update Flash Ai Assistant Io 2024', doc.data['title']
      # the slug still comes from the raw title, so post URLs are unchanged
      assert_equal 'google-blog-google-gemini-update-flash-ai-assistant-io-2024', doc.basename_without_ext
      assert_equal url, doc.data['redirect']
    end
  end

  def test_rss_entry_without_a_title_is_published_with_a_derived_title
    entries = [
      OpenStruct.new(
        url: 'https://example.com/feed/an-untitled-entry/',
        title: nil,
        content: '<p>Body</p>',
        summary: 'Summary',
        published: Time.utc(2024, 1, 2)
      )
    ]

    with_site do |site|
      capture_jekyll_warnings { @generator.process_entries(site, { 'name' => 'Example Source' }, entries) }
      doc = site.collections['posts'].docs.last

      assert_equal 'An Untitled Entry', doc.data['title']
    end
  end
end
