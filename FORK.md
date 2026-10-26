# Fork maintenance

This fork tracks `ao-data/albiondata-client` with no source changes. Two workflows handle upkeep:

- **Sync upstream** (`sync-upstream.yml`): runs daily, merges `upstream/master` into `master`, pushes new tags, and builds a release for any new upstream tag. Run it by hand from the Actions tab.
- **Fork release** (`fork-release.yml`): builds the Windows exe, update archive, and installer from a tag and publishes them as a release on this fork. The self-updater is pointed at this fork during the build, so installed copies update from your releases rather than upstream's.

If upstream changes files in `.github/workflows`, the default token can't push them. Add a repo secret `SYNC_TOKEN` (personal access token, `repo` + `workflow` scopes).

Keep your own changes in separate commits and avoid editing upstream files where possible, so merges stay clean.

## Custom changes vs upstream

- `client/debug_format.go`: `debugFormatMaxString` raised from 240 to 4096 so `-debug` output keeps whole JSON order strings. `extras/AlbionMarketLogger.ps1` parses that output into CSV and breaks if the strings are truncated. A test in `client/debug_format_test.go` guards it.

Because the fork's self-updater points at this fork's releases, the patch survives updates. If a sync ever conflicts on that line in `debug_format.go`, keep the raised value.
