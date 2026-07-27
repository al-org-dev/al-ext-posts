# Changelog

## 1.0.3 - 2026-07-27

- Fixed external posts being published with an empty title when a fetch degraded (an unreachable page, a page with no `<title>`, or an RSS item with a blank one), which rendered as a blank but clickable row in the blog index and produced a stream of Jekyll ``Empty `slug` generated`` warnings. A readable title is now derived from the URL's last meaningful path segment, and a warning naming the URL is logged. Post slugs, and therefore post URLs, are unchanged.

## 1.0.2 - 2026-07-27

- Optimized external-post slug generation: the title check no longer allocates a stripped copy of the title, character filtering runs in a single regexp pass instead of two, and the source-name fallback is only built when it is actually needed. Slug output is unchanged.

## 1.0.1 - 2026-05-24

- Preserved source-level categories/tags while allowing RSS entries and explicit external posts to override them.
- Hardened tests against local timezone differences and current Minitest releases.

## 0.1.0 - 2026-02-07

- Initial gem release.
- Added external post import from RSS feeds and explicit URL lists.
- Added RSS parse error handling and per-source default categories/tags.
