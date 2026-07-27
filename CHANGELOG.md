# Changelog

## 1.0.2 - 2026-07-27

- Optimized external-post slug generation: the title check no longer allocates a stripped copy of the title, character filtering runs in a single regexp pass instead of two, and the source-name fallback is only built when it is actually needed. Slug output is unchanged.

## 1.0.1 - 2026-05-24

- Preserved source-level categories/tags while allowing RSS entries and explicit external posts to override them.
- Hardened tests against local timezone differences and current Minitest releases.

## 0.1.0 - 2026-02-07

- Initial gem release.
- Added external post import from RSS feeds and explicit URL lists.
- Added RSS parse error handling and per-source default categories/tags.
