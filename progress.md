# Jusou Progress

Last updated: 2026-05-17

This file records the current development state and implementation details so future work can resume without reconstructing context from chat history.

## Project Snapshot

Jusou is a Flutter resource search app. It aggregates local indexes, JSON source files, and configurable remote search sources, then performs client-side normalization, deduplication, ranking, validation, favorites, recent-opened records, search history, and invalid-link reports.

Primary local data locations:

```text
~/.jusou/index.json
~/.jusou/sources/*.json
```

Main verification commands:

```bash
/Users/lobster/myprojects/flutter/bin/flutter analyze
/Users/lobster/myprojects/flutter/bin/flutter test
```

Latest full verification passed on 2026-05-17:

- `flutter analyze`: no issues found.
- `flutter test`: all tests passed.

## Current Feature Status

### Search and Aggregation

Implemented:

- Local index source from `~/.jusou/index.json`.
- Custom JSON sources from `~/.jusou/sources/*.json`.
- Remote source fallback list, configured from settings or environment.
- Query variant normalization, including common Chinese variant matching such as `狂飚` -> `狂飙`.
- Deduplication across share-link variants and duplicate titles.
- Ranking by keyword match, validation level, source trust, metadata completeness, freshness, duplicate count, and title-noise penalty.
- Source status display for success, empty, partial failure, and failure.

Key files:

- `lib/data/services/resource_service.dart`
- `lib/data/services/resource_aggregator.dart`
- `lib/data/services/resource_deduper.dart`
- `lib/data/services/resource_ranker.dart`
- `lib/data/services/resource_text_normalizer.dart`

### Remote Search Sources

Implemented:

- Generic remote JSON adapter: `RemoteSearchSource`.
- Generic adapter contract: request `GET /api/search?kw=<query>` and parse JSON response.
- Supports response shapes using `data.merged_by_type`, `data.results`, or `data.items`.
- HTML responses from generic remote sources now fail with a clear message instead of silently decoding as empty JSON.
- Dedicated `alipansou.com` adapter: `AlipansouSearchSource`.

Important detail:

`alipansou.com` is not compatible with the generic JSON API adapter. It returns HTML search pages and a JS challenge page before allowing access. The app now detects `alipansou.com`, `www.alipansou.com`, and the bare domain `alipansou.com`, then routes them through the dedicated adapter.

`AlipansouSearchSource` implementation:

- Searches `/search?k=<query>`.
- Detects the challenge page via `id="ori"`, `start_load(...)`, and `ck_ml_sea_`.
- Computes the challenge cookie using AES-CBC with PKCS7 padding and key/IV `1234567812345678`.
- Parses search result cards from HTML anchors such as `/s/<token>`.
- Extracts title from `name="content-title"`.
- Extracts date, format, and size from the card metadata line.
- Resolves `/cv/<token>` with redirects disabled to capture the real `Location` header, usually an `https://www.alipan.com/s/...` URL.
- Falls back to the `/cv/<token>` URL if the real share URL cannot be resolved.

Key files:

- `lib/data/services/remote_search_source.dart`
- `lib/data/services/alipansou_search_source.dart`
- `lib/data/services/resource_service.dart`

Dependency added:

- `pointycastle`, used for AES-CBC/PKCS7 challenge-cookie generation.

### Link Identity and Validation

Implemented:

- Common share-link parsing for Aliyun/Alipan, Quark, Baidu, UC, Xunlei, 115, and 123pan.
- Canonical resource keys via `ResourceKey`, so equivalent share links such as `aliyundrive.com/s/<id>` and `alipan.com/s/<id>` map to the same identity.
- Favorites, validation cache, recent-opened records, and invalid reports use canonical keys where relevant.
- Link validator rejects demo placeholders like `example`, `demo`, `sample`, and `test`.
- Network validation falls back from `HEAD` to lightweight `GET` when the server does not confirm `HEAD`.

Key files:

- `lib/data/services/share_link_parser.dart`
- `lib/data/services/resource_key.dart`
- `lib/data/services/link_validator.dart`
- `lib/data/services/local_library_service.dart`

### Resource Model and Metadata

Implemented:

- `Resource.fromJson` accepts snake_case and camelCase variants for common fields.
- Resource type normalization supports:
  - `movie`
  - `tv`
  - `documentary`
  - `variety`
- UI category list includes movie, TV, documentary, and variety.

Key files:

- `lib/data/models/resource.dart`
- `lib/data/services/resource_service.dart`
- `lib/presentation/pages/home_page_helpers.dart`

### Home Page and UI

Implemented:

- Main search page with search bar, filters, result list, detail sheet, favorite, copy, open, validate, and invalid-report actions.
- Filters for provider, type, year, extraction code, validation state, and multi-source merged results.
- Sort modes: relevance, latest, multi-source (by duplicate count), and file size.
- Empty-state guidance when no local or remote data source is configured.
- Settings sheet for remote search:
  - Enable or disable remote search.
  - Up to 5 remote URLs.
  - Drag to reorder remote URL priority.
  - Delete URLs.
  - Reordering preserves controller text.
- `home_page.dart` has been split into part files to reduce file size:
  - `home_page_helpers.dart`
  - `home_page_widgets.dart`

Key files:

- `lib/presentation/pages/home_page.dart`
- `lib/presentation/pages/home_page_helpers.dart`
- `lib/presentation/pages/home_page_widgets.dart`

### Persistence

Implemented:

- Favorites.
- Recently opened resources.
- Search history.
- Invalid link reports.
- Validation cache.
- Library settings, including remote search enabled flag and ordered remote URL list.

Key files:

- `lib/data/models/local_library.dart`
- `lib/data/services/local_library_service.dart`

### Data Crawlers

A Node.js crawler suite exists under `crawler/` to populate local data sources. It is not part of the Flutter build but is documented here because it produces the data the app consumes.

Implemented:

- `crawler/index.js`: Generic crawler framework with adapter-based site parsing; writes to `~/.jusou/index.json`.
- `crawler/tg_crawler.js`: Telegram public-channel crawler; extracts share links from messages and writes to `~/.jusou/sources/telegram.json`.
- `crawler/channels.txt`: Channel list for the TG crawler.
- Supports providers: alipan, aliyun, quark, uc, xunlei, 115, 123pan, baidu, pikpak.

Key files:

- `crawler/index.js`
- `crawler/tg_crawler.js`
- `crawler/channels.txt`

### Deferred / Placeholder Features

These modules exist in the codebase but are not wired into the active user flow:

- **Aliyun Drive OAuth save-to-drive** (`lib/data/services/aliyun_drive_service.dart`):
  - Only a stub. `login()` and `saveToDrive()` throw `UnsupportedError`.
  - Requires OAuth app registration, token refresh, file listing, target folder selection, and save-state polling before it can be enabled.
  - Current user flow is: open share link in browser → copy link / extraction code → manual save.
- **AppState model** (`lib/data/models/app_state.dart`):
  - Defines `currentRoute`, `currentQuery`, `isLoggedIn`.
  - Not imported or used anywhere in the project. Left as a placeholder for future navigation or auth state management.

### Build and Release

Implemented or updated:

- macOS and Windows project files exist.
- Release documentation references macOS and Windows packages.
- GitHub release workflow runs tests.
- README documents local data sources and remote source behavior.

Key files:

- `.github/workflows/release.yml`
- `README.md`
- `RELEASE.md`

## Test Coverage Added or Updated

Main test file:

- `test/data/services/resource_pipeline_test.dart`

Covered behavior:

- Chinese query variant normalization.
- Share link parser provider recognition.
- Placeholder share-link rejection.
- HEAD-to-GET validation fallback.
- Resource JSON round-trip and type normalization.
- Canonical resource keys.
- Deduplication and ranking.
- Query variant retries.
- Configured data-source detection.
- Source status failures.
- `alipansou.com` adapter selection for bare domain.
- Alipansou challenge cookie computation.
- Alipansou HTML card parsing and `/cv` redirect resolution.
- Local library persistence behavior using in-memory mode.

Widget test:

- `test/widget_test.dart`
- Confirms the app shows the search field.

## Current Git State Notes

As of this update, the project has a mix of staged and unstaged work from the ongoing implementation. Do not blindly reset the working tree.

Files intentionally added during this development pass include:

- `AGENTS.md`
- `lib/data/services/resource_key.dart`
- `lib/data/services/alipansou_search_source.dart`
- `lib/presentation/pages/home_page_helpers.dart`
- `lib/presentation/pages/home_page_widgets.dart`
- `progress.md`

Before committing, review staged and unstaged changes with:

```bash
git status --short
git diff --cached --name-status
git diff --name-status
```

## Known Risks and Constraints

- `alipansou.com` support depends on its current HTML structure and JS challenge logic. If the site changes `start_load`, cookie name, card markup, or `/cv` redirect behavior, the adapter may need updating.
- The dedicated alipansou adapter is site-specific and should not be treated as the generic remote API contract.
- Generic remote URLs still need to expose compatible JSON at `/api/search?kw=<query>`.
- Remote site scraping can be fragile. Keep failures visible in source status rather than hiding them as empty results.
- The current app has no built-in default remote URL. Users must configure remote URLs or provide local JSON/index files.
- Link validation can confirm format and page reachability, but it does not fully verify file availability inside every cloud drive provider.

## Suggested Next Steps

1. Add integration-level manual testing for configured remote URL ordering:
   - First URL `alipansou.com`.
   - Search `主角`.
   - Confirm results appear and opening a result goes to an Alipan share page where possible.

2. Add more site adapters only behind explicit host detection:
   - Do not route arbitrary websites through `RemoteSearchSource`.
   - Keep generic JSON API and site-specific adapters separate.

3. Improve source status visibility:
   - Show clearer user-facing messages for "HTML returned instead of JSON API".
   - Consider exposing the active remote source label in fallback results.

4. Decide commit boundaries:
   - One commit for core search/data improvements.
   - One commit for UI refactor/settings reorder.
   - One commit for `alipansou.com` adapter.
   - One commit for documentation/progress tracking.

5. Consider adding a small adapter registry:
   - Host detection currently lives in `ResourceService._remoteSourceForUrl`.
   - If more adapters are added, move this into a dedicated registry/factory.

## Resume Checklist

When resuming work:

1. Run `git status --short`.
2. Read this file.
3. Run `flutter analyze` and `flutter test` if code changed.
4. Preserve user changes and do not reset the working tree.
5. Keep remote source behavior split between:
   - Generic JSON API: `RemoteSearchSource`.
   - Host-specific adapters: `AlipansouSearchSource` and future equivalents.
