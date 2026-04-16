import fs from 'fs';
import path from 'path';

describe('DarkRP task3 annotation coverage', () => {
  test('task3 files exist (vars + chat hooks)', () => {
    const annotationsDir = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations');
    const expectedFiles = [
      'darkrp-vars.lua',
      'darkrp-chat-hooks.lua',
    ];

    for (const fileName of expectedFiles) {
      expect(fs.existsSync(path.join(annotationsDir, fileName))).toBe(true);
    }
  });

  test('task3 var annotations expose registration + player var surface', () => {
    const varsLua = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations', 'darkrp-vars.lua');

    expect(fs.existsSync(varsLua)).toBe(true);

    const content = fs.readFileSync(varsLua, 'utf8');
    expect(content).toMatch(/^\s*function\s+DarkRP\.registerDarkRPVar\s*\(/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.writeNetDarkRPVar\s*\(\s*varName\s*,\s*value\s*\)/m);
    expect(content).not.toMatch(/^\s*function\s+DarkRP\.writeNetDarkRPVar\s*\(\s*varName\s*,\s*value\s*,\s*target\s*\)/m);
    expect(content).toMatch(/---@overload\s+fun\(varName:\s*"agenda",\s*value:\s*string\)/);
    expect(content).toMatch(/---@overload\s+fun\(varName:\s*"Energy",\s*value:\s*number\)/);
    expect(content).toMatch(/^\s*function\s+DarkRP\.readNetDarkRPVar\s*\(\s*\)/m);
    expect(content).toMatch(/^\s*function\s+Player:getDarkRPVar\s*\(\s*varName\s*,\s*fallback\s*\)/m);
    expect(content).toMatch(/^\s*function\s+Player:setDarkRPVar\s*\(\s*varName\s*,\s*value\s*,\s*target\s*\)/m);
    expect(content).toMatch(/^\s*function\s+Player:removeDarkRPVar\s*\(\s*varName\s*,\s*target\s*\)/m);
    expect(content).toMatch(/---@overload\s+fun\(self:\s*Player,\s*varName:\s*"Energy",\s*fallback\?:\s*number\):\s*number\?/);
    expect(content).toMatch(/---@overload\s+fun\(self:\s*Player,\s*varName:\s*"hitTarget",\s*value:\s*Player,\s*target\?:\s*Player\|Player\[\]\)/);
    expect(content).toMatch(/^\s*function\s+Player:sendDarkRPVars\s*\(\s*\)/m);
  });

  test('task3 chat annotations expose declaration/definition surfaces', () => {
    const chatLua = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations', 'darkrp-chat-hooks.lua');

    expect(fs.existsSync(chatLua)).toBe(true);

    const content = fs.readFileSync(chatLua, 'utf8');
    expect(content).toMatch(/^\s*function\s+DarkRP\.declareChatCommand\s*\(\s*tbl\s*\)/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.defineChatCommand\s*\(\s*command\s*,\s*callback\s*\)/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.removeChatCommand\s*\(\s*command\s*\)/m);
    expect(content).toMatch(/---@field\s+tableArgs\?\s+boolean/);
    expect(content).toMatch(
      /---@alias\s+DarkRPDefineChatCommandCallback\s+fun\(ply:\s*Player,\s*args:\s*string\|string\[\]/,
    );
    expect(content).toMatch(/---@alias\s+DarkRPDefineChatCommandCallback\s+fun\(.*\):\s*DarkRPChatCommandResult,\s*DarkRPDoSayFunc\?/);
    expect(content).toMatch(/---@alias\s+DarkRPChatCommandCanRun\s+fun\(ply:\s*Player\):\s*boolean/);
    expect(content).toMatch(/---@field\s+description\s+string/);
    expect(content).toMatch(/---@field\s+delay\s+DarkRPChatCommandDelay/);
    expect(content).not.toMatch(/---@field\s+table\?\s+/);
    expect(content).not.toMatch(/---@field\s+requiresArg\?\s+/);
  });
});
