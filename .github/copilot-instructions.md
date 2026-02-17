# GMod EmmyLua Annotation Generator Instructions

## Project Overview
This repository is an **annotation generator**, not a runtime plugin.

Primary responsibility:
1. **Wiki Scraper (TypeScript)**: Scrapes the GMod Wiki to gather API metadata.
2. **Annotation Writer (TypeScript)**: Converts metadata into EmmyLua/LuaCATS annotation files (`output/*.lua`).

Generated annotations are consumed by the GMod `emmylua-analyzer-rust` language server workflow.

## Architecture

### 1. Wiki Scraper + Writer Pipeline
- **Entry point**: `src/cli-scraper.ts`
- **Core logic**:
    - `scrapers/`: Parses wiki HTML/data into normalized structures.
    - `api-writer/`: Converts normalized structures into EmmyLua/LuaCATS annotations.
- **Output**: Generated annotation files in `output/` (e.g., `output/entity.lua`, `output/globals.lua`).

### 2. Override System
- `custom/` contains manual overrides used by generation.
- Files prefixed with `_` (e.g., `_globals.lua`) are copied directly.
- Other override files are merged into generated docs.

## Critical Workflows

### Working on generator logic
- **Generate output**: `npm run scrape-wiki`
- **Run tests**: `npm test` (Jest in `__tests__/`)
- **Create release artifacts locally** (legacy): `npm run pack-release` (`*.lua.zip`)

### Release behavior (GitHub Actions)
- Releases run from `.github/workflows/release.yml`.
- Workflow checks whether wiki data changed and publishes updated annotations to the `emmylua-annotations` branch.
- The VSCode extension automatically downloads annotations from this branch for end-user consumption.

## Conventions & Patterns
- **EmmyLua/LuaCATS-first**: Prefer correct annotations and stable output structure.
- **Generated-over-manual**: Most annotation content should be produced by scraper/writer logic, not hand-edited output files.
- **Override discipline**: Use `custom/` only when generator logic cannot cleanly express the fix yet.
- **Test coverage**: Any behavior change in scraper/writer should include or update Jest tests.
