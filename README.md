# GMod EmmyLua Annotation Generator

> **Forked from** [luttje/glua-api-snippets](https://github.com/luttje/glua-api-snippets)
> Original project by luttje - converted for EmmyLua analyzer integration

Automatically generates EmmyLua annotations for Garry's Mod API by scraping the [GMod Wiki](https://wiki.facepunch.com/gmod/). These annotations are consumed by [gmod-glua-ls](https://github.com/Pollux12/gmod-glua-ls).

**Note**: This repository is part of the GMod language server infrastructure.
Annotations are automatically downloaded by the VSCode extension from the `emmylua-annotations` branch - manual setup is not required for end users.

## Workflow

1. `npm run wiki-check-changed` checks whether upstream wiki content changed since the latest scrape tag.
2. `npm run scrape-wiki` scrapes and normalizes wiki pages, then writes Lua annotations into `output/`.
3. `npm test` validates scraper and writer behavior.
4. CI formats generated output and publishes annotations to the `emmylua-annotations` branch for extension consumption.

## Development Setup

Requirements:

- Node.js `>= 21`

Install dependencies:

```bash
npm ci
```

Generate annotations locally:

```bash
npm run scrape-wiki
```

Run tests:

```bash
npm test
```

Build release artifact locally (legacy, not required for branch-based consumption):

```bash
npm run pack-release
```

## Local Development Testing

For local language server testing, generate annotations and point your workspace library to `./output/`:

```json
{
  "workspace": {
    "library": [
      "./output"
    ]
  }
}
```

**Note**: The VSCode extension automatically downloads production annotations from the `emmylua-annotations` branch. The above configuration is only needed for testing local changes during development.

## Repository Layout

- `src/scrapers/` - GMod wiki scraping and normalization
- `src/api-writer/` - EmmyLua/LuaCATS annotation generation
- `custom/` - manual overrides merged during generation
- `output/` - generated annotation files (published to `emmylua-annotations` branch)
