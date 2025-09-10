import packageJson from '../package.json' with { type: "json" };
import { GluaApiWriter } from './api-writer/glua-api-writer.js';
import { makeConfigJson } from './utils/lua-language-server.js';
import { readMetadata } from './utils/metadata.js';
import { walk } from './utils/filesystem.js';
import { Command } from 'commander';
import path from 'path';
import fs from 'fs';

const libraryName = 'garrysmod';

// Patterns to recognize in GLua files, so that the language server can recommend this library to be activated:
const libraryWordMatchers = [
  'include%s*%(?',
  'AddCSLuaFile%s*%(?',
  'hook%.Add%s*%(',
];

// Same as above, but for files:
const libraryFileMatchers: string[] = [];
const libraryDirectory = 'library';

async function main() {
  const program = new Command();

  program
    .version(packageJson.version)
    .description('Publishes the previously scraped Garry\'s Mod wiki API information as a LuaLS Library')
    .option('-i, --input <path>', 'The path to the directory where the output json and lua files have been saved', './output')
    .option('-o, --output <path>', 'The path to the directory where the release should be saved', './dist/libraries/garrysmod')
    .parse(process.argv);

  const options = program.opts();

  if (!options.input) {
    console.error('No input path provided');
    process.exit(1);
  }

  if (!options.output) {
    console.error('No output path provided');
    process.exit(1);
  }

  const metadata = await readMetadata(options.input);

  if (!metadata) {
    console.error('No metadata found');
    process.exit(1);
  }

  if (!fs.existsSync(path.join(options.output, libraryDirectory))) {
    fs.mkdirSync(path.join(options.output, libraryDirectory), { recursive: true });
  }

  console.log(`Building Lua Language Server Library for ${metadata.lastUpdate}...`);

  const config = makeConfigJson(
    libraryName,
    libraryWordMatchers,
    libraryFileMatchers,
    {
      "Lua.runtime.version": "LuaJIT",
      "Lua.runtime.special": {
        "include": "require",
        "IncludeCS": "require",
      },
      "Lua.runtime.nonstandardSymbol": [
        "!",
        "!=",
        "&&",
        "||",
        "//",
        "/**/",
        "continue",
      ],
      "Lua.diagnostics.disable": [
        "duplicate-set-field", // Prevents complaining when a function exists twice in both the CLIENT and SERVER realm
      ],
      // TODO: runtime.path
    });

  fs.writeFileSync(path.join(options.output, 'config.json'), JSON.stringify(config, null, 2));

  // Include plugin.lua and plugin modules at the root of the library output so users can reference it via Lua.runtime.plugin
  console.log('Copying plugin files to library output...');

  // Get the root directory (where plugin files are located)
  const rootDir = process.cwd();

  // Copy main plugin files
  const pluginFiles = [
    { src: 'plugin.lua', dest: 'plugin.lua' },
    { src: 'config.lua', dest: 'config.lua' }
  ];

  for (const { src, dest } of pluginFiles) {
    const srcPath = path.join(rootDir, src);
    const destPath = path.join(options.output, dest);

    if (fs.existsSync(srcPath)) {
      fs.copyFileSync(srcPath, destPath);
      console.log(`Copied ${src} to library output`);
    } else {
      console.warn(`Plugin file ${src} not found, skipping...`);
    }
  }

  // Copy the plugin modules folder
  const pluginModulesDir = path.join(rootDir, 'plugin');
  const outputPluginDir = path.join(options.output, 'plugin');

  if (fs.existsSync(pluginModulesDir)) {
    if (!fs.existsSync(outputPluginDir)) {
      fs.mkdirSync(outputPluginDir, { recursive: true });
    }

    const moduleFiles = walk(pluginModulesDir, (file, isDirectory) => isDirectory || file.endsWith('.lua'));
    moduleFiles.forEach((file) => {
      const relativePath = path.relative(pluginModulesDir, file);
      const outputPath = path.join(outputPluginDir, relativePath);

      // Ensure the directory exists
      const outputDir = path.dirname(outputPath);
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }

      fs.copyFileSync(file, outputPath);
    });
    console.log('Copied plugin modules to library output');
  } else {
    console.warn('Plugin modules directory not found, skipping...');
  }

  // Also copy plugin files to the input directory so pack-release can find them
  console.log('Copying plugin files to input directory for release packing...');

  for (const { src, dest } of pluginFiles) {
    const srcPath = path.join(rootDir, src);
    const destPath = path.join(options.input, dest);

    if (fs.existsSync(srcPath)) {
      fs.copyFileSync(srcPath, destPath);
    }
  }

  // Copy plugin modules to input directory
  const inputPluginDir = path.join(options.input, 'plugin');
  if (fs.existsSync(pluginModulesDir)) {
    if (!fs.existsSync(inputPluginDir)) {
      fs.mkdirSync(inputPluginDir, { recursive: true });
    }

    const moduleFiles = walk(pluginModulesDir, (file, isDirectory) => isDirectory || file.endsWith('.lua'));
    moduleFiles.forEach((file) => {
      const relativePath = path.relative(pluginModulesDir, file);
      const outputPath = path.join(inputPluginDir, relativePath);

      // Ensure the directory exists
      const outputDir = path.dirname(outputPath);
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }

      fs.copyFileSync(file, outputPath);
    });
  }

  const files = walk(options.input, (file, isDirectory) => {
    if (isDirectory) return true;
    if (file.endsWith('.lua')) return true;
    if (file.endsWith('__metadata.json')) return true;
    return false;
  });

  files.forEach((file) => {
    const relativePath = path.relative(options.input, file);
    const outputPath = path.join(options.output, libraryDirectory, relativePath);

    // Ensure the directory exists
    const outputDir = path.dirname(outputPath);
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    fs.copyFileSync(file, outputPath);
  });

  console.log(`Done building Library! It can be found @ ${options.output}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
