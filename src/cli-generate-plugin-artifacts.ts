import { Command } from 'commander';
import path from 'path';
import { pathToFileURL } from 'url';
import {
  DEFAULT_PLUGIN_ARTIFACT_MANIFEST,
  DEFAULT_PLUGIN_BRANCH_PREFIX,
} from './plugin-index.js';
import { generatePluginArtifacts } from './plugin-artifacts.js';

async function main() {
  const program = new Command();
  program
    .description('Generate plugin index and local plugin bundle artifacts')
    .option('--pluginRoot <path>', 'Path to source plugin root', './plugin')
    .option('--indexOutput <path>', 'Path for canonical plugin index output', './plugin/index.json')
    .option('--annotationsOutput <path>', 'Path to annotation output root', './output')
    .option('--pluginBundlesOutput <path>', 'Path to local plugin bundles output root', './output-plugins')
    .option('--branchPrefix <prefix>', 'Branch prefix for generated artifact refs', DEFAULT_PLUGIN_BRANCH_PREFIX)
    .option('--artifactManifest <path>', 'Manifest file name published in artifact refs', DEFAULT_PLUGIN_ARTIFACT_MANIFEST)
    .option('--version <version>', 'Optional artifact version')
    .option('--generatedAt <timestamp>', 'Optional generatedAt timestamp');

  program.parse(process.argv);
  const options = program.opts<{
    pluginRoot: string;
    indexOutput: string;
    annotationsOutput: string;
    pluginBundlesOutput: string;
    branchPrefix: string;
    artifactManifest: string;
    version?: string;
    generatedAt?: string;
  }>();

  generatePluginArtifacts({
    pluginRoot: path.resolve(options.pluginRoot),
    indexOutput: path.resolve(options.indexOutput),
    annotationsOutput: path.resolve(options.annotationsOutput),
    pluginBundlesOutput: path.resolve(options.pluginBundlesOutput),
    branchPrefix: options.branchPrefix,
    artifactManifest: options.artifactManifest,
    version: options.version,
    generatedAt: options.generatedAt,
  });

  console.log(`Generated plugin artifacts in ${path.resolve(options.annotationsOutput)}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
