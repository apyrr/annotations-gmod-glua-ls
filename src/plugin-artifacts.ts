import fs from 'fs';
import path from 'path';
import {
  DEFAULT_PLUGIN_ARTIFACT_MANIFEST,
  DEFAULT_PLUGIN_BRANCH_PREFIX,
  buildPluginIndex,
  loadSourcePluginBundles,
  writePluginIndex,
} from './plugin-index.js';

export type GeneratePluginArtifactsOptions = {
  pluginRoot: string;
  indexOutput: string;
  annotationsOutput: string;
  pluginBundlesOutput?: string;
  branchPrefix?: string;
  artifactManifest?: string;
  version?: string;
  generatedAt?: string;
};

function isSafeChildPath(rootPath: string, candidatePath: string): boolean {
  const relative = path.relative(rootPath, candidatePath);
  return !relative.startsWith('..') && !path.isAbsolute(relative);
}

function isSameOrChildPath(rootPath: string, candidatePath: string): boolean {
  const relative = path.relative(rootPath, candidatePath);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

export function generatePluginArtifacts(options: GeneratePluginArtifactsOptions): void {
  const pluginRoot = path.resolve(options.pluginRoot);
  const indexOutput = path.resolve(options.indexOutput);
  const annotationsOutput = path.resolve(options.annotationsOutput);
  const pluginBundlesOutput = path.resolve(options.pluginBundlesOutput ?? `${annotationsOutput}-plugins`);
  if (isSameOrChildPath(annotationsOutput, pluginBundlesOutput)) {
    throw new Error('pluginBundlesOutput must be outside annotationsOutput');
  }
  if (isSameOrChildPath(pluginRoot, pluginBundlesOutput)) {
    throw new Error('pluginBundlesOutput must be outside pluginRoot');
  }
  if (isSameOrChildPath(pluginBundlesOutput, annotationsOutput)) {
    throw new Error('pluginBundlesOutput must not contain annotationsOutput');
  }
  if (isSameOrChildPath(pluginBundlesOutput, pluginRoot)) {
    throw new Error('pluginBundlesOutput must not contain pluginRoot');
  }
  if (isSameOrChildPath(pluginBundlesOutput, path.dirname(indexOutput))) {
    throw new Error('pluginBundlesOutput must not contain indexOutput directory');
  }
  const bundles = loadSourcePluginBundles(pluginRoot);
  const index = buildPluginIndex(bundles, {
    branchPrefix: options.branchPrefix ?? DEFAULT_PLUGIN_BRANCH_PREFIX,
    artifactManifest: options.artifactManifest ?? DEFAULT_PLUGIN_ARTIFACT_MANIFEST,
    version: options.version,
    generatedAt: options.generatedAt,
  });

  writePluginIndex(indexOutput, index);
  writePluginIndex(path.join(annotationsOutput, 'plugin', 'index.json'), index);

  const bundleRoot = pluginBundlesOutput;
  fs.rmSync(bundleRoot, { recursive: true, force: true });
  fs.mkdirSync(bundleRoot, { recursive: true });

  for (const bundle of bundles) {
    const sourceDir = path.resolve(bundle.dirPath);
    const sourceGluarcPath = path.resolve(sourceDir, bundle.manifest.gluarcPath ?? bundle.manifest.gluarc ?? 'gluarc.json');
    if (!isSafeChildPath(sourceDir, sourceGluarcPath)) {
      throw new Error(`Invalid gluarc path for plugin "${bundle.id}"`);
    }

    const sourceAnnotationsPath = path.resolve(sourceDir, bundle.manifest.annotationsPath ?? 'annotations');
    if (!isSafeChildPath(sourceDir, sourceAnnotationsPath)) {
      throw new Error(`Invalid annotations path for plugin "${bundle.id}"`);
    }

    const outputBundleDir = path.join(bundleRoot, bundle.id);
    fs.mkdirSync(outputBundleDir, { recursive: true });
    fs.copyFileSync(sourceGluarcPath, path.join(outputBundleDir, 'gluarc.json'));

    if (fs.existsSync(sourceAnnotationsPath) && fs.statSync(sourceAnnotationsPath).isDirectory()) {
      fs.cpSync(sourceAnnotationsPath, path.join(outputBundleDir, 'annotations'), { recursive: true });
    }

    fs.writeFileSync(
      path.join(outputBundleDir, 'plugin.json'),
      `${JSON.stringify({
        id: bundle.id,
        label: bundle.manifest.label,
        description: bundle.manifest.description ?? '',
        gluarcPath: 'gluarc.json',
        annotationsPath: 'annotations',
      }, null, 2)}\n`,
      'utf8',
    );
  }
}
