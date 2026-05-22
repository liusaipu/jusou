# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get              # install dependencies
flutter run -d macos         # run desktop app (also: -d chrome, -d windows)
flutter analyze              # static analysis (must pass; CI gate)
flutter test                 # full test suite
flutter test test/data/services/resource_pipeline_test.dart   # single file
flutter test --plain-name 'normalizes Aliyun'                 # single test by name
flutter build macos --release    # build release artifacts (CI uses this)
flutter build windows --release
```

CI (`.github/workflows/release.yml`) is triggered by `v*` tags and runs `flutter analyze` + `flutter test` + `flutter build` for macOS and Windows. Flutter version is pinned to `3.41.9`.

The Node.js crawler under `crawler/` is independent of the Flutter app and only contains the generic index crawler:

```bash
cd crawler && npm install && node index.js
```

Telegram-channel crawling has moved into the Flutter app (`lib/data/services/telegram_crawler.dart`) and is triggered from the settings sheet.

## Architecture

Jusou is a Flutter desktop/web app that aggregates resource search across **pluggable sources**. The core abstraction is `ResourceSource` (`lib/data/services/resource_source.dart`) — any source (local index, JSON file, remote API, alipansou web adapter) implements `search(query) → SourceSearchResult`.

### Search pipeline

A single search request flows through this pipeline (`lib/data/services/`):

1. **`ResourceService`** is the entrypoint. It builds the source list from `~/.jusou/index.json`, `~/.jusou/sources/*.json`, and configured remote URLs. It implements **sequential fallback**: only the first remote URL is added to the aggregator; if the aggregator returns 0 results, it retries each additional remote URL in order.
2. **`ResourceAggregator`** fans out the query to all sources in parallel (with query variants from `ResourceTextNormalizer` to handle Chinese variant characters like 飚/飙), then runs validation → dedupe → ranking.
3. **`LinkValidator`** classifies links (URL format → recognized provider → reachable → invalid) using HEAD-with-GET-fallback, results cached.
4. **`ResourceDeduper`** merges duplicates by a tiered key: share-link identity (via `ShareLinkParser`, which canonicalizes equivalent hosts like `aliyundrive.com` ↔ `alipan.com`), then canonical URL, then `title+year+filesize`. Merged groups keep the highest-quality candidate and union the `mergedSources` list.
5. **`ResourceRanker`** sorts by relevance / latest / multi-source-trust / file-size depending on UI selection.

When extending sources, the `_remoteSourceForUrl` factory dispatches to `AlipansouSearchSource` (HTML scraper with JS-challenge handling) for `alipansou.com` URLs, and the generic `RemoteSearchSource` (expects `/api/search?kw=...` JSON) otherwise.

### State and persistence

- No BLoC despite `flutter_bloc` being in deps — UI state lives in `HomePage` (`lib/presentation/pages/home_page.dart`, split across `home_page.dart` / `home_page_widgets.dart` / `home_page_helpers.dart` via `part` files).
- **Hive** (`LocalLibraryService`) persists favorites, recently-opened, search history, invalid-link reports, link-validation cache, and user settings. Falls back to in-memory map if Hive init fails.
- User settings (dark mode, remote URL list, enable-remote flag, Telegram channel list) are also mirrored to `~/.jusou/config.json`.

### Data conventions

- `Resource` model accepts both `snake_case` and `camelCase` JSON keys (external JSON sources are mixed).
- Type field is normalized to `movie` / `tv` / `documentary` / `variety`.
- Environment overrides for testing: `JUSOU_ENABLE_REMOTE`, `JUSOU_REMOTE_URL`.

### Crawler

`crawler/index.js` is the generic Node.js crawler used to seed `~/.jusou/index.json` from various resource sites. **Crawler output is untrusted input** — the validation/dedupe pipeline above is what makes it safe to consume.

Telegram-channel crawling is built into the app via `lib/data/services/telegram_crawler.dart`. It reads the channel list from `LibrarySettings.telegramChannels` (persisted in Hive and `~/.jusou/config.json`) and writes `~/.jusou/sources/telegram.json`, which `ResourceService` picks up on next launch.

## Project guidelines (from AGENTS.md)

- State assumptions explicitly before implementing; ask when uncertain rather than picking silently.
- Surgical changes only — don't refactor or reformat adjacent code that wasn't part of the request.
- Remove imports/variables your changes orphaned; leave pre-existing dead code alone unless asked.
