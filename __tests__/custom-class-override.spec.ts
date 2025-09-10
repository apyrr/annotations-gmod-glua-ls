import fs from 'fs';
import path from 'path';
import { GluaApiWriter } from '../src/api-writer/glua-api-writer.js';

describe('Custom class overrides emission', () => {
	const tmpDir = path.join(process.cwd(), 'output_test_tmp');

	beforeAll(() => {
		if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
	});

	afterAll(() => {
		if (fs.existsSync(tmpDir)) {
			fs.rmSync(tmpDir, { recursive: true, force: true });
		}
	});

	test('orphan class override (class.ENT) is written when no wiki page exists', () => {
		const writer = new GluaApiWriter(tmpDir);
		writer.addOverride('class.ENT', '@---@class ENT\nENT = {}\n');
		writer.writeToDisk();
		const customFile = path.join(tmpDir, 'custom_classes.lua');
		expect(fs.existsSync(customFile)).toBe(true);
		const content = fs.readFileSync(customFile, 'utf8');
		expect(content).toMatch(/@class ENT/);
		expect(content).toMatch(/ENT = {}/);
	});
});
