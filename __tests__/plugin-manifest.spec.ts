import fs from 'fs';
import os from 'os';
import path from 'path';
import {
  buildPluginIndex,
  generatePluginIndex,
  loadSourcePluginBundles,
  DEFAULT_PLUGIN_ARTIFACT_MANIFEST,
  DEFAULT_PLUGIN_BRANCH_PREFIX,
  type GeneratedPluginIndex,
} from '../src/plugin-index';

function validatePluginIds(ids: string[]) {
  const duplicate = ids.find((id, index) => ids.indexOf(id) !== index);
  if (duplicate) {
    throw new Error(`Duplicate plugin id: ${duplicate}`);
  }
}

describe('plugin manifests', () => {
  const pluginRoot = path.join(process.cwd(), 'plugin');

  test('source plugin bundles are valid and deterministic', () => {
    const bundles = loadSourcePluginBundles(pluginRoot);
    const sortedIds = [...bundles.map((bundle) => bundle.id)].sort((a, b) => a.localeCompare(b));
    expect(bundles.map((bundle) => bundle.id)).toEqual(sortedIds);

    for (const bundle of bundles) {
      const gluarcPath = path.join(bundle.dirPath, bundle.manifest.gluarcPath ?? 'gluarc.json');
      expect(fs.existsSync(gluarcPath)).toBe(true);
      const hasBaseSignals = !!bundle.manifest.detection.gamemodeBases?.length;
      const hasFolderSignals = !!bundle.manifest.detection.folderNamePatterns?.length;
      const hasManifestSignals = !!bundle.manifest.detection.manifestPatterns?.length;
      const hasFileNameSignals = !!bundle.manifest.detection.fileNamePatterns?.length;
      const hasGlobalNameSignals = !!bundle.manifest.detection.globalNames?.length || !!bundle.manifest.detection.globals?.length;
      const hasGlobalPatternSignals = !!bundle.manifest.detection.globalPatterns?.length;
      expect(
        hasBaseSignals ||
        hasFolderSignals ||
        hasManifestSignals ||
        hasFileNameSignals ||
        hasGlobalNameSignals ||
        hasGlobalPatternSignals,
      ).toBe(true);
      expect(bundle.manifest.label).toBeTruthy();
      expect(typeof bundle.manifest.description).toBe('string');
    }
  });

  test('index file matches generated registry schema', () => {
    const bundles = loadSourcePluginBundles(pluginRoot);
    const expectedIndex = buildPluginIndex(bundles);
    const actualIndex = generatePluginIndex(pluginRoot) as GeneratedPluginIndex;

    const normalize = (index: GeneratedPluginIndex): GeneratedPluginIndex => ({
      plugins: index.plugins.map((plugin) => ({
        ...plugin,
        artifact: {
          branch: plugin.artifact.branch,
          manifest: plugin.artifact.manifest,
        },
      })),
    });

    expect(normalize(actualIndex)).toEqual(normalize(expectedIndex));
    for (const plugin of actualIndex.plugins) {
      expect(plugin.label).toBeTruthy();
      expect(typeof plugin.description).toBe('string');
      expect(plugin.artifact.branch).toBe(`${DEFAULT_PLUGIN_BRANCH_PREFIX}${plugin.id}`);
      expect(plugin.artifact.manifest).toBe(DEFAULT_PLUGIN_ARTIFACT_MANIFEST);
      if (plugin.artifact.version !== undefined) {
        expect(plugin.artifact.version).toBeTruthy();
      }
      const hasBaseSignals = !!plugin.detection.gamemodeBases?.length;
      const hasFolderSignals = !!plugin.detection.folderNamePatterns?.length;
      const hasManifestSignals = !!plugin.detection.manifestPatterns?.length;
      const hasFileNameSignals = !!plugin.detection.fileNamePatterns?.length;
      const hasGlobalNameSignals = !!plugin.detection.globalNames?.length;
      const hasGlobalPatternSignals = !!plugin.detection.globalPatterns?.length;
      expect(
        hasBaseSignals ||
        hasFolderSignals ||
        hasManifestSignals ||
        hasFileNameSignals ||
        hasGlobalNameSignals ||
        hasGlobalPatternSignals,
      ).toBe(true);
    }
  });

  test('duplicate ids are rejected', () => {
    expect(() => validatePluginIds(['helix', 'helix'])).toThrow('Duplicate plugin id: helix');
  });

  test('plugin id must match folder name for CI publishing', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gluals-plugin-index-'));
    const pluginDir = path.join(tmpRoot, 'custom-folder');
    fs.mkdirSync(pluginDir, { recursive: true });
    fs.writeFileSync(path.join(pluginDir, 'gluarc.json'), JSON.stringify({ gmod: {} }, null, 2), 'utf8');
    fs.writeFileSync(path.join(pluginDir, 'plugin.json'), JSON.stringify({
      id: 'custom-id',
      label: 'Custom',
      description: 'Custom plugin',
      detection: { folderNamePatterns: ['custom'] },
      gluarcPath: 'gluarc.json',
    }, null, 2), 'utf8');

    try {
      expect(() => loadSourcePluginBundles(tmpRoot)).toThrow(
        'Plugin id "custom-id" must match folder name "custom-folder"',
      );
    } finally {
      fs.rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  test('plugin id must be a safe slug', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gluals-plugin-index-'));
    const pluginDir = path.join(tmpRoot, 'bad id');
    fs.mkdirSync(pluginDir, { recursive: true });
    fs.writeFileSync(path.join(pluginDir, 'gluarc.json'), JSON.stringify({ gmod: {} }, null, 2), 'utf8');
    fs.writeFileSync(path.join(pluginDir, 'plugin.json'), JSON.stringify({
      id: 'bad id',
      label: 'Bad',
      description: 'Bad id plugin',
      detection: { folderNamePatterns: ['bad'] },
      gluarcPath: 'gluarc.json',
    }, null, 2), 'utf8');

    try {
      expect(() => loadSourcePluginBundles(tmpRoot)).toThrow(
        'Plugin id "bad id" must match /^[a-z0-9][a-z0-9-]*$/',
      );
    } finally {
      fs.rmSync(tmpRoot, { recursive: true, force: true });
    }
  });
});
