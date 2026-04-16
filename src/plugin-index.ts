import fs from 'fs';
import path from 'path';

export type SourcePluginManifest = {
  id: string;
  label: string;
  description?: string;
  detection: {
    gamemodeBases?: string[];
    folderNamePatterns?: string[];
    manifestPatterns?: string[];
  };
  gluarcPath?: string;
  gluarc?: string;
  annotationsPath?: string;
};

export type GeneratedPluginIndexEntry = {
  id: string;
  label: string;
  description: string;
  detection: {
    gamemodeBases?: string[];
    folderNamePatterns?: string[];
    manifestPatterns?: string[];
  };
  artifact: {
    branch: string;
    manifest: string;
    version?: string;
  };
};

export type GeneratedPluginIndex = {
  generatedAt?: string;
  plugins: GeneratedPluginIndexEntry[];
};

export type SourcePluginBundle = {
  id: string;
  dirName: string;
  dirPath: string;
  manifest: SourcePluginManifest;
};

export type BuildPluginIndexOptions = {
  branchPrefix?: string;
  artifactManifest?: string;
  version?: string;
  generatedAt?: string;
};

export const DEFAULT_PLUGIN_BRANCH_PREFIX = 'gluals-annotations-plugin-';
export const DEFAULT_PLUGIN_ARTIFACT_MANIFEST = 'plugin.json';
const PLUGIN_ID_REGEX = /^[a-z0-9][a-z0-9-]*$/;

function asString(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((entry): entry is string => typeof entry === 'string')
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}

function isObjectRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function normalizeDetection(value: unknown): GeneratedPluginIndexEntry['detection'] {
  if (!isObjectRecord(value)) {
    throw new Error('Missing "detection" object');
  }

  const gamemodeBases = asStringArray(value.gamemodeBases);
  const folderNamePatterns = asStringArray(value.folderNamePatterns);
  const manifestPatterns = asStringArray(value.manifestPatterns);

  if (
    gamemodeBases.length === 0
    && folderNamePatterns.length === 0
    && manifestPatterns.length === 0
  ) {
    throw new Error('detection requires at least one signal');
  }

  return {
    ...(gamemodeBases.length > 0 ? { gamemodeBases } : {}),
    ...(folderNamePatterns.length > 0 ? { folderNamePatterns } : {}),
    ...(manifestPatterns.length > 0 ? { manifestPatterns } : {}),
  };
}

export function loadSourcePluginBundles(pluginRoot: string): SourcePluginBundle[] {
  if (!fs.existsSync(pluginRoot) || !fs.statSync(pluginRoot).isDirectory()) {
    throw new Error(`Plugin root does not exist: ${pluginRoot}`);
  }

  const bundles: SourcePluginBundle[] = [];
  for (const entry of fs.readdirSync(pluginRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }

    const dirPath = path.join(pluginRoot, entry.name);
    const manifestPath = path.join(dirPath, 'plugin.json');
    if (!fs.existsSync(manifestPath)) {
      continue;
    }

    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as SourcePluginManifest;
    const id = asString(manifest.id);
    if (!id) {
      throw new Error(`Plugin at "${entry.name}" is missing a valid "id"`);
    }
    if (id !== entry.name) {
      throw new Error(`Plugin id "${id}" must match folder name "${entry.name}"`);
    }
    if (!PLUGIN_ID_REGEX.test(id)) {
      throw new Error(`Plugin id "${id}" must match ${PLUGIN_ID_REGEX.toString()}`);
    }

    const label = asString(manifest.label);
    if (!label) {
      throw new Error(`Plugin "${id}" is missing a valid "label"`);
    }

    const detection = normalizeDetection(manifest.detection);
    const gluarcPath = asString(manifest.gluarcPath)
      ?? asString(manifest.gluarc)
      ?? 'gluarc.json';
    const gluarcAbsolutePath = path.join(dirPath, gluarcPath);
    if (!fs.existsSync(gluarcAbsolutePath) || !fs.statSync(gluarcAbsolutePath).isFile()) {
      throw new Error(`Plugin "${id}" references missing gluarc file: ${gluarcPath}`);
    }

    const annotationsPath = asString(manifest.annotationsPath) ?? 'annotations';
    bundles.push({
      id,
      dirName: entry.name,
      dirPath,
      manifest: {
        ...manifest,
        id,
        label,
        description: asString(manifest.description) ?? '',
        detection,
        gluarcPath,
        annotationsPath,
      },
    });
  }

  bundles.sort((a, b) => a.id.localeCompare(b.id));

  const ids = bundles.map((bundle) => bundle.id);
  const duplicateId = ids.find((id, index) => ids.indexOf(id) !== index);
  if (duplicateId) {
    throw new Error(`Duplicate plugin id: ${duplicateId}`);
  }

  return bundles;
}

export function buildPluginIndex(
  bundles: readonly SourcePluginBundle[],
  options: BuildPluginIndexOptions = {},
): GeneratedPluginIndex {
  const branchPrefix = options.branchPrefix ?? DEFAULT_PLUGIN_BRANCH_PREFIX;
  const artifactManifest = options.artifactManifest ?? DEFAULT_PLUGIN_ARTIFACT_MANIFEST;
  const version = asString(options.version);
  const generatedAt = asString(options.generatedAt);

  const plugins = bundles
    .map((bundle) => ({
      id: bundle.id,
      label: bundle.manifest.label,
      description: bundle.manifest.description ?? '',
      detection: bundle.manifest.detection,
      artifact: {
        branch: `${branchPrefix}${bundle.id}`,
        manifest: artifactManifest,
        ...(version ? { version } : {}),
      },
    }))
    .sort((a, b) => a.id.localeCompare(b.id));

  return {
    ...(generatedAt ? { generatedAt } : {}),
    plugins,
  };
}

export function generatePluginIndex(
  pluginRoot: string,
  options: BuildPluginIndexOptions = {},
): GeneratedPluginIndex {
  const bundles = loadSourcePluginBundles(pluginRoot);
  return buildPluginIndex(bundles, options);
}

export function writePluginIndex(outputPath: string, index: GeneratedPluginIndex): void {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(index, null, 2)}\n`, 'utf8');
}
