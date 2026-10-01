# Snaplist

A native iPhone app for a personal, searchable archive: receipts, statements,
bills, warranties, manuals, and notes about where things are. Photograph or
import them; find them again by what they say.

Everything stays on the phone. There is no account and no server.

## Status

Built: capture (scan, photos, files, voice notes), on-device text reading and
transcription, automatic names and categories, search that lands on the page,
receipt/bill totals and statement lines (correctable, each linked to where it
was printed), Ask (spending totals, where something is, warranty expiry), and
a Face ID lock.

Not yet: export and delete-everything in Settings, App Intents and Spotlight,
iCloud sync.

## Building

You need a Mac with Xcode 26 or newer.

```
brew install xcodegen
xcodegen generate
open Snaplist.xcodeproj
```

The Xcode project is generated from `project.yml` and not committed. The
document camera does not exist in the simulator; use photos and files there,
or run on a device.

CI (`.github/workflows/ci.yml`) runs the core tests on Linux and builds the
app for the simulator on a hosted Mac, on every push.

The core package also builds and tests anywhere Swift 6 runs:

```
swift test --package-path Packages/ArchiveCore
```

## TestFlight

`.github/workflows/testflight.yml`, run by hand from the Actions tab, archives,
signs (automatic, cloud-managed) and uploads a build. Build numbers are
`1000 + run number`. It needs four repository secrets:

| Secret | What |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | the API key's ID |
| `APP_STORE_CONNECT_ISSUER_ID` | the issuer ID shown above the keys list |
| `APP_STORE_CONNECT_KEY` | the whole `.p8` file, including the BEGIN/END lines |
| `APPLE_TEAM_ID` | the 10-character team ID |

The key needs the Admin role (or App Manager with access to cloud-managed
distribution certificates) so Xcode can create the signing certificate.

## How it is put together

```
Packages/ArchiveCore/          plain Swift + SQLite; no Apple-only frameworks
  Model.swift                  Record, Asset (an original file), Page, TextLine
  ArchiveStore.swift           the database: schema, reads, writes, the index
  Search.swift                 full-text search, one hit per record, snippets
  ArchiveFiles.swift           originals on disk, one folder per record
  Archive.swift                adds and deletes across both, failing safe
  Ingestor.swift               pending record -> text -> ready (or failed)
Snaplist/
  App/                         app entry, AppModel (list, search, imports)
  Security/AppLock             Face ID / passcode lock, app-switcher cover
  Capture/DocumentScanner      VisionKit's document camera
  Extraction/                  Vision OCR, PDF text layer, page rendering
  Views/                       list + search, record detail, page view
```

**Storage.** SQLite through GRDB, not SwiftData: search needs FTS5 ranking
and spending totals (a later phase) need exact SQL sums, neither of which
SwiftData offers; and the store can be tested off-device. Originals are kept
byte-for-byte in Application Support with complete file protection, so they
cannot be read while the phone is locked.

**Text.** Images are read with Vision's `RecognizeTextRequest`, keeping each
line's position so matches can be highlighted on the page. A PDF page's own
text layer is used when it has one, and rendered and OCR'd when it does not.
OCR makes mistakes; the app says which text was machine-read.

**Import.** Originals are saved immediately and the record appears as
"Reading text…"; text is read in the background and the record becomes
searchable when it is done. A failure is kept on the record with a reason
and a retry, never silently dropped.

## How answers work

Questions are read by `QuestionParser` with plain rules, so they work on every
iPhone and the same words always mean the same thing. Spending totals are sums
of stored integer cents (`ArchiveStore.answer`), never a language model's
arithmetic, and every amount counted is listed with the record it came from.
A receipt and its statement line (same amount, a few days apart, same kind of
merchant) count once. When no statement covers the period asked about, the
answer says so; when nothing matches, it says that instead of guessing.

## Plan

1. ~~Capture, storage, OCR, search with links to the page.~~
2. ~~Organise and correct; voice notes; Face ID lock.~~
3. ~~Receipt and statement extraction, with correction.~~
4. ~~Questions with exact, cited answers.~~
5. Duplicates: today they're counted once in answers; next, show them on the
   records and let the person merge or keep both.
6. Privacy and system: export, delete everything, App Intents and Spotlight.
7. Optional: Foundation Models (where Apple Intelligence is available) to read
   unusual phrasings into the same structured question. It would never add up
   amounts.

Later: iCloud sync, household sharing, a paid tier.
