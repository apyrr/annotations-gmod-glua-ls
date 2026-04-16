import fs from 'fs';
import os from 'os';
import path from 'path';
import { spawnSync } from 'child_process';

describe('cli-generate-lua', () => {
  test('ignores non-page JSON payloads such as plugin index metadata', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gluals-generate-lua-'));
    const outputPath = path.join(tmpRoot, 'output');
    const pluginBundlesPath = path.join(tmpRoot, 'output-plugins');
    const pluginDir = path.join(outputPath, 'plugin');
    const hooksDir = path.join(outputPath, 'hooks');

    fs.mkdirSync(pluginDir, { recursive: true });
    fs.mkdirSync(hooksDir, { recursive: true });
    fs.writeFileSync(path.join(pluginDir, 'index.json'), JSON.stringify({ plugins: [] }, null, 2), 'utf8');
    fs.writeFileSync(path.join(hooksDir, 'pages.json'), JSON.stringify([], null, 2), 'utf8');

    try {
      const command = process.platform === 'win32' ? 'npm.cmd' : 'npm';
      const result = spawnSync(
        `${command} run generate-lua -- --output "${outputPath}" --customOverrides ./custom`,
        [],
        {
          cwd: process.cwd(),
          encoding: 'utf8',
          shell: true,
        },
      );

      expect(result.status).toBe(0);
      expect(result.stderr).not.toContain('TypeError: pages.forEach is not a function');
      expect(fs.existsSync(path.join(pluginBundlesPath, 'darkrp', 'plugin.json'))).toBe(false);
    } finally {
      fs.rmSync(tmpRoot, { recursive: true, force: true });
    }
  });
});
