# Fork notes

This is a personal fork of [pounat/absorb](https://github.com/pounat/absorb). It exists to make Absorb work well with BookOrbit on one phone. Keep the difference from upstream as small as possible so syncing stays cheap.

Last synced with upstream: `761ec117` (Bump to 1.12.1+301), 2026-10-24.

## Rules

1. New behaviour goes in fork-owned files under a `fork/` folder. Upstream files only get small hooks that call into them.
2. A hook is the fewest lines that can reach the fork code. Do not reformat, rename or reorder upstream code.
3. Every changed path under `lib/`, `android/`, `ios/` or `pubspec.yaml` must be listed in this file before it is committed. The pre-commit hook (`.githooks/pre-commit`) enforces it.
4. Do not commit regenerated `lib/l10n/app_localizations_*.dart` and do not add translation strings. New text is a plain constant until upstream takes it.
5. Sync by rebasing: `git fetch upstream && git rebase upstream/main`, then update the date and commit above. `git config rerere.enabled true` is on.
6. Send generic improvements upstream as small separate PRs. When one is accepted, delete its row below.

Setup on a fresh clone:

```bash
git config core.hooksPath .githooks
git config rerere.enabled true
```

To skip the check once (for example resolving a rebase conflict), run the commit with `FORK_NOTES_SKIP=1`.

## Fork-owned files

| File | What it does |
| --- | --- |
| `lib/widgets/fork/book_detail_fork.dart` | BookOrbit book detail layout: header, main and secondary action buttons, icon row, tag chips, and their helpers. A `part` of `book_detail_sheet.dart`. |
| `lib/services/fork/bookorbit_dashboard.dart` | The Dashboard virtual library (shelves from BookOrbit's cross-library scrollers) and the per-book cover frame helper. A `part` of `api_service.dart`. |
| `FORK_NOTES.md` | This file. |
| `.githooks/pre-commit` | Refuses a commit that changes tracked app files without a matching entry here. |

## Hooks in upstream files

| File | Change | Upstream PR candidate |
| --- | --- | --- |
| `lib/widgets/book_detail_sheet.dart` | Imports the fork `part`; `_buildContent` calls `_forkActionButtons`, `_forkDetailHeader`, `_forkIconRow`, `_forkTagChips`; `_loadCoverShape` uses the book's own frame; cover URLs pass `coverRatio`; `_tagsExpanded` field; the old header, buttons and chip code was removed from here. | Yes, the layout |
| `lib/services/api_service.dart` | `part 'fork/bookorbit_dashboard.dart'`; `getCoverUrl` takes `coverRatio` (ignored for Audiobookshelf). | Yes |
| `lib/services/bookorbit_api_service.dart` | `dashboardLibraryId`; the `global` branches in `_personalized` (shelves from `/dashboard/scrollers`); the dashboard route hook; `_forkWithFrame` calls stamp `media.coverAspectRatio`; `getCoverUrl` maps `coverRatio` to the audio or ebook cover; `_listCoverSlot` reads the server shape; `loadCoverShape` fills `PlayerSettings.serverRectByLibrary` and runs after libraries load. | Yes |
| `lib/services/player_settings.dart` | `serverRectByLibrary` map, used by `getRectangleCoversFor` after a per-library override. | Yes |
| `lib/providers/_lp_state.dart` | `_homeDashboard`, `homeDashboard`, `_homeLibId`, `canShowDashboard`, `_personalizedInFlightFor`; `getCoverUrl` takes `coverRatio`. | Maybe |
| `lib/providers/_lp_core.dart` | `setHomeDashboard`, `_resetHomeDashboard`; Home fetches, caches and progress shelves use `_homeLibId`; in-flight fetch is reused only for the same Home. | Maybe |
| `lib/providers/library_provider.dart` | Resets the Dashboard on login and logout. | Maybe |
| `lib/widgets/library_picker_sheet.dart` | `forHome` option and a Dashboard row. | Maybe |
| `lib/screens/home_screen.dart` | Passes `forHome: true`; Home pill says Dashboard; `_ContinueListeningCard` draws a book in its own frame on the Dashboard. | Maybe |
| `lib/widgets/home_section.dart` | Mixed-shape shelves on the Dashboard: same height, square covers wider, no snap scrolling. | Maybe |
| `lib/widgets/book_card.dart` | Passes `coverRatio` when asking for the cover. | Yes |
| `lib/widgets/library_grid_tiles.dart` | Passes `coverRatio` when asking for the cover. | Yes |
| `lib/widgets/absorbing_shared.dart` | `DownloadWideButton(compact: true)`: icon only with a tooltip. | Yes |

## Local only (never committed)

- `android/key.properties` and `~/.android/absorb-fork.jks`: signing for sideloaded builds. Keep the same key forever; Android will not update an app signed with a different one.
