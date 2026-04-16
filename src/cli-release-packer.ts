import { convertWindowsToUnixPath, dateToFilename, walk } from './utils/filesystem.js';
import packageJson from '../package.json' with { type: "json" };
import { readMetadata } from './utils/metadata.js';
import { Command } from 'commander';
import path from 'path';
import fs from 'fs';
import archiver from 'archiver';
import { pathToFileURL } from 'url';

type ReleasePackOptions = {
  inputPath: string;
  outputPath: string;
  pluginPath: string;
}

type ReleaseEntry = {
  sourcePath: string;
  archivePath: string;
}

function collectReleaseEntries(inputPath: string, pluginPath: string): ReleaseEntry[] {
  const inputEntries = walk(inputPath, (file, isDirectory) => {
    if (isDirectory) return true;
    if (!file.endsWith('.lua')) return false;

    const relativePath = path.relative(inputPath, file).replace(/\\/g, '/');
    if (relativePath === 'plugin.lua' || relativePath === 'config.lua') return false;
    if (relativePath.startsWith('plugin/')) return false;

    return true;
  }).map((sourcePath) => ({
    sourcePath,
    archivePath: path.relative(inputPath, sourcePath).replace(/\\/g, '/'),
  }));

  const pluginEntries = fs.existsSync(pluginPath)
    ? walk(pluginPath, (file, isDirectory) => isDirectory || path.basename(file) !== '.DS_Store')
      .map((sourcePath) => ({
        sourcePath,
        archivePath: path.posix.join('plugin', path.relative(pluginPath, sourcePath).replace(/\\/g, '/')),
      }))
    : [];

  return [...inputEntries, ...pluginEntries]
    .sort((a, b) => a.archivePath.localeCompare(b.archivePath));
}

async function createReleaseArchive(targetPath: string, entries: ReleaseEntry[]) {
  await new Promise<void>((resolve, reject) => {
    const outputDirectory = path.dirname(targetPath);
    if (!fs.existsSync(outputDirectory))
      fs.mkdirSync(outputDirectory, { recursive: true });

    const output = fs.createWriteStream(targetPath);
    const archive = archiver.create('zip', { zlib: { level: 9 } });
    output.on('close', () => resolve());
    archive.on('error', (error) => reject(error));
    archive.pipe(output);

    for (const entry of entries) {
      archive.file(entry.sourcePath, { name: entry.archivePath });
    }

    void archive.finalize();
  });
}

export async function buildReleasePackage(options: ReleasePackOptions) {
  const metadata = await readMetadata(options.inputPath);

  if (!metadata) {
    throw new Error('No metadata found');
  }

  console.log(`Building release for ${metadata.lastUpdate}...`);

  const baseFileName = dateToFilename(metadata.lastUpdate);
  const targetPath = path.join(options.outputPath, `${baseFileName}.lua.zip`);
  const entries = collectReleaseEntries(options.inputPath, options.pluginPath);

  await createReleaseArchive(targetPath, entries);

  const releaseFiles = [convertWindowsToUnixPath(targetPath)];

  fs.writeFileSync(path.join(options.outputPath, 'release.json'), JSON.stringify({
    version: metadata.lastUpdate.toLocaleString(),
    tag: baseFileName,
    releaseFiles,
  }));

  console.log(`Done building release! It can be found @ ${releaseFiles.join(' and ')}`);
  return { archivePath: targetPath, releaseFiles, tag: baseFileName };
}

async function main() {
  const program = new Command();

  program
    .version(packageJson.version)
    .description('Releases the previously scraped Garry\'s Mod wiki API information')
    .option('-i, --input <path>', 'The path to the directory where the output lua annotation files have been saved', './output')
    .option('-o, --output <path>', 'The path to the directory where the release should be saved', './dist/release')
    .option('-p, --plugin <path>', 'The path to the plugin manifest directory', './plugin')
    .parse(process.argv);

  const options = program.opts();

  if (!options.input) {
    console.error('No input path provided');
    process.exit(1);
  }

  await buildReleasePackage({
    inputPath: options.input,
    outputPath: options.output,
    pluginPath: options.plugin,
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
