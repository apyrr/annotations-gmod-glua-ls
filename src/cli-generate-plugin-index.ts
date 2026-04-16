import { Command } from 'commander';
import path from 'path';
import { pathToFileURL } from 'url';
import {
  DEFAULT_PLUGIN_BRANCH_PREFIX,
  generatePluginIndex,
  writePluginIndex,
} from './plugin-index.js';

async function main() {
  const program = new Command();

  program
    .description('Generate plugin index metadata for annotation publishing')
    .option('--pluginRoot <path>', 'Path to plugin manifest source root', './plugin')
    .option('--output <path>', 'Path to write generated plugin index json', './plugin/index.json')
    .option('--branchPrefix <prefix>', 'Branch name prefix for plugin artifacts', DEFAULT_PLUGIN_BRANCH_PREFIX)
    .option('--version <version>', 'Artifact version string included in each plugin entry')
    .option('--generatedAt <timestamp>', 'Optional generatedAt timestamp');

  program.parse(process.argv);
  const options = program.opts<{
    pluginRoot: string;
    output: string;
    branchPrefix: string;
    version?: string;
    generatedAt?: string;
  }>();

  const pluginRoot = path.resolve(options.pluginRoot);
  const outputPath = path.resolve(options.output);

  const index = generatePluginIndex(pluginRoot, {
    branchPrefix: options.branchPrefix,
    version: options.version,
    generatedAt: options.generatedAt,
  });
  writePluginIndex(outputPath, index);
  console.log(`Generated plugin index at ${outputPath}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
