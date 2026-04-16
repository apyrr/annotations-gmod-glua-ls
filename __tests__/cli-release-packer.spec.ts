import StreamZip from 'node-stream-zip';
import fs from 'fs';
import path from 'path';
import { buildReleasePackage } from '../src/cli-release-packer';

describe('cli-release-packer', () => {
  const tmpRoot = path.join(process.cwd(), 'output_test_tmp_release');
  const inputDir = path.join(tmpRoot, 'input');
  const outputDir = path.join(tmpRoot, 'dist');
  const pluginDir = path.join(tmpRoot, 'plugin');

  beforeEach(() => {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
    fs.mkdirSync(inputDir, { recursive: true });
    fs.mkdirSync(outputDir, { recursive: true });
    fs.mkdirSync(path.join(pluginDir, 'helix'), { recursive: true });

    fs.writeFileSync(path.join(inputDir, '__metadata.json'), JSON.stringify({
      lastUpdate: '2026-04-14T00:00:00.000Z',
    }));
    fs.writeFileSync(path.join(inputDir, 'globals.lua'), 'print("globals")\n');
    fs.writeFileSync(path.join(inputDir, 'config.lua'), '-- legacy config\n');
    fs.writeFileSync(path.join(inputDir, 'plugin.lua'), '-- legacy plugin\n');
    fs.mkdirSync(path.join(inputDir, 'plugin'), { recursive: true });
    fs.writeFileSync(path.join(inputDir, 'plugin', 'legacy.lua'), '-- legacy nested plugin\n');

    fs.writeFileSync(path.join(pluginDir, 'index.json'), JSON.stringify({ plugins: [] }, null, 2));
    fs.writeFileSync(path.join(pluginDir, 'README.md'), '# plugin contract\n');
    fs.writeFileSync(path.join(pluginDir, 'helix', 'plugin.json'), JSON.stringify({ id: 'helix' }, null, 2));
  });

  afterAll(() => {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  test('includes plugin artifacts and keeps legacy excludes', async () => {
    const { archivePath } = await buildReleasePackage({
      inputPath: inputDir,
      outputPath: outputDir,
      pluginPath: pluginDir,
    });

    const zip = new StreamZip.async({ file: archivePath });
    const entries = Object.keys(await zip.entries()).sort();
    await zip.close();

    expect(entries).toContain('globals.lua');
    expect(entries).toContain('plugin/index.json');
    expect(entries).toContain('plugin/README.md');
    expect(entries).toContain('plugin/helix/plugin.json');

    expect(entries).not.toContain('config.lua');
    expect(entries).not.toContain('plugin.lua');
    expect(entries).not.toContain('plugin/legacy.lua');
  });
});
