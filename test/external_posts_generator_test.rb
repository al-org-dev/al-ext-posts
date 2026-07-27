require 'minitest/autorun'
require 'ostruct'
require 'date'
require 'time'

require_relative '../lib/al_ext_posts'

class AlExtPostsGeneratorTest < Minitest::Test
  class CaptureGenerator < AlExtPosts::ExternalPostsGenerator
    attr_reader :calls

    def initialize
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
end
