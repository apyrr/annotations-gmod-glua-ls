# Plugin manifest contract

Each plugin directory must contain:

- `plugin.json`: plugin metadata consumed by tooling.
- `gluarc.json`: preset patch that can be merged into a project `.gluarc.json`.

## `plugin/index.json`

- `plugins`: ordered list of plugin entries.
- Every entry must include:
  - `id` (unique, deterministic sort key)
  - `manifest` (relative path to `plugin.json`)

## `plugin.json` required keys

- `id`: stable plugin ID.
- `label`: human-readable name.
- `detection`: at least one signal (`gamemodeBases` and/or `folderNamePatterns`).
- `gluarc`: relative path to plugin `gluarc.json`.
