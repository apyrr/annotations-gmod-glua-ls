import fs from 'fs';
import os from 'os';
import path from 'path';
import { generatePluginArtifacts } from '../src/plugin-artifacts';

describe('plugin artifacts generation', () => {
  function seedPlugin(pluginRoot: string) {
    const pluginDir = path.join(pluginRoot, 'darkrp');
    fs.mkdirSync(path.join(pluginDir, 'annotations'), { recursive: true });
    fs.writeFileSync(path.join(pluginDir, 'annotations', 'darkrp.lua'), '---@meta\n', 'utf8');
    fs.writeFileSync(path.join(pluginDir, 'gluarc.json'), JSON.stringify({
      diagnostics: { globals: ['DarkRP'] },
    }, null, 2), 'utf8');
    fs.writeFileSync(path.join(pluginDir, 'plugin.json'), JSON.stringify({
      id: 'darkrp',
      label: 'DarkRP',
      description: 'DarkRP plugin',
      detection: { gamemodeBases: ['darkrp'] },
      gluarcPath: 'gluarc.json',
      annotationsPath: 'annotations',
    }, null, 2), 'utf8');
  }

  test('generates local plugin index and sibling plugin bundles output', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gluals-plugin-artifacts-'));
    const pluginRoot = path.join(root, 'plugin');
    const annotationsOutput = path.join(root, 'output');
    const pluginBundlesOutput = path.join(root, 'output-plugins');
    const indexOutput = path.join(pluginRoot, 'index.json');
    seedPlugin(pluginRoot);

    try {
      generatePluginArtifacts({
        pluginRoot,
        indexOutput,
        annotationsOutput,
        pluginBundlesOutput,
      });

      const localIndexPath = path.join(annotationsOutput, 'plugin', 'index.json');
      const localBundleManifestPath = path.join(pluginBundlesOutput, 'darkrp', 'plugin.json');
      const localBundleGluarcPath = path.join(pluginBundlesOutput, 'darkrp', 'gluarc.json');
      const localBundleAnnotationPath = path.join(pluginBundlesOutput, 'darkrp', 'annotations', 'darkrp.lua');

      expect(fs.existsSync(indexOutput)).toBe(true);
      expect(fs.existsSync(localIndexPath)).toBe(true);
      expect(fs.existsSync(localBundleManifestPath)).toBe(true);
      expect(fs.existsSync(localBundleGluarcPath)).toBe(true);
      expect(fs.existsSync(localBundleAnnotationPath)).toBe(true);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });

  test('rejects plugin bundle output paths nested under annotation output', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gluals-plugin-artifacts-'));
    const pluginRoot = path.join(root, 'plugin');
    const annotationsOutput = path.join(root, 'output');
    const indexOutput = path.join(pluginRoot, 'index.json');
    seedPlugin(pluginRoot);

    try {
      expect(() => generatePluginArtifacts({
        pluginRoot,
        indexOutput,
        annotationsOutput,
        pluginBundlesOutput: path.join(annotationsOutput, 'plugin-bundles'),
      })).toThrow('pluginBundlesOutput must be outside annotationsOutput');
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });

  test('rejects plugin bundle output paths that contain plugin root', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gluals-plugin-artifacts-'));
    const annotationsRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gluals-plugin-artifacts-ann-'));
    const pluginRoot = path.join(root, 'plugin');
    const annotationsOutput = path.join(annotationsRoot, 'output');
    const indexOutput = path.join(pluginRoot, 'index.json');
    seedPlugin(pluginRoot);

    try {
      expect(() => generatePluginArtifacts({
        pluginRoot,
        indexOutput,
        annotationsOutput,
        pluginBundlesOutput: root,
      })).toThrow('pluginBundlesOutput must not contain pluginRoot');
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
      fs.rmSync(annotationsRoot, { recursive: true, force: true });
    }
  });
});
