# GMod LuaLS Addon & Scraper Instructions

## Project Overview
This repository contains two distinct components working together to provide Garry's Mod Lua support in VS Code (via LuaLS):
1.  **Wiki Scraper (TypeScript)**: Scrapes the GMod Wiki to generate Lua definition files (`output/*.lua`).
2.  **LuaLS Plugin (Lua)**: A runtime plugin (`plugin.lua`) for Lua Language Server that enhances analysis (custom classes, Derma, NetworkVars).

**Crucial Distinction**: 
-   The **TypeScript** code (`src/`) is a build tool. It runs *before* the user uses the library.
-   The **Lua** code (`plugin.lua`) is a runtime plugin. It runs *inside* the user's IDE/LuaLS process.

## Architecture

### 1. Wiki Scraper (Generator)
-   **Entry Point**: `src/cli-scraper.ts`
-   **Core Logic**:
    -   `scrapers/`: Parses wiki HTML to structured data.
    -   `api-writer/`: Converts structured data into LuaCATS annotations (Lua files).
-   **Output**: Generates files in `output/` (e.g., `output/entity.lua`, `output/globals.lua`).
-   **Overrides**: `custom/` contains manual override files.
    -   Files starting with `_` (e.g., `_globals.lua`) are copied directly to output.
    -   Other files (e.g., `BaseClass.Get.lua`) are merged into the generated documentation.

### 2. LuaLS Plugin (Runtime)
-   **File**: `plugin.lua`
-   **Purpose**: Intersects LuaLS execution to provide dynamic intelligence that static files cannot (e.g., `SWEP.Base` inheritance, `NetworkVar` generation).
-   **Configuration**: Handles `config.lua` (defaults) and `.glua-api-snippets.json` (workspace overrides).
-   **Testing**: There are **NO automated tests** for the Lua plugin. Changes must be verified manually or by code review.

## Critical Workflows

### Working with the Scraper
-   **Build & Run**: `npm run scrape-wiki` (updates `output/` folder).
-   **Testing**: `npm test` runs Jest tests in `__tests__/`. **Always run tests after modifying TypeScript**.
-   **Release**: `npm run build-plugin` (publishes library and packs release).

### Working with the Plugin
-   **Editing**: Edit `plugin.lua` directly.
-   **Validation**: Since there are no tests, rely on static analysis and careful logic verification.
-   **Context**: The plugin runs *inside* the Lua Language Server process. It exploits `bee.filesystem` and `parser` libraries provided by LuaLS.

## Conventions & Patterns
-   **LuaCATS**: Output files use LuaCATS annotations (`---@class`, `---@field`).
-   **Wiki Parsing**: The scraper handles wiki quirks. API definitions are generated, not manually written (except `custom/`).
-   **Plugin AST**: The plugin modifies the AST (`OnSetText`, `OnTransformAst`). It splits `PANEL` locals to fix LuaLS scoping issues.
-   **Globals**: `_G` modifications should be avoided in the plugin; use locally scoped fixes where possible.
