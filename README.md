# mobile-android

Part of the muxd22-alt monorepo consolidation (50 repos -> 5).

Every member lives in `repos/<name>/` and stays self-contained.
Identical CI configs across the old repos were replaced by the single,
shared workflow set in `.github/workflows/`:

- **CI** — structure, oversized-file, secret and syntax checks on every push/PR
- **Daily Digest** — scheduled 06:00 UTC, publishes a per-member activity table
  to the `Daily Digest` issue and the job summary

## Members

| folder | language | files | size | merged (absorbed repos) |
|---|---|---:|---:|---|
| `APHONE` | Python | 5 | 0.1 MB | — |
| `Deepin_OGC_Intel` | HTML | 9 | 0.0 MB | — |
| `SubArabify` | JavaScript | 49 | 4.6 MB | — |
| `TallDuoLauncher` | Kotlin | 250 | 3.4 MB | `TALL_DuoLauncher` |
| `bc250-steamos-real-toolkit` | Python | 3745 | 194.6 MB | — |
| `openclaw-android` | — | 7 | 6.6 MB | — |
| `openclaw_arbor_backup` | — | 174 | 6.3 MB | — |
| `termux_reader` | TypeScript | 564 | 13.6 MB | — |

See `SOURCE_MAP.md` for the old-repo -> new-path mapping, including files
kept under `repos/<x>/_variants/` (conflicting versions from absorbed repos).
