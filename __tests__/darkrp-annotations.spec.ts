import fs from 'fs';
import path from 'path';

describe('DarkRP split annotation coverage', () => {
  test('task2 split files exist (customthings + config)', () => {
    const annotationsDir = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations');
    const expectedFiles = [
      'darkrp-customthings.lua',
      'darkrp-config.lua',
    ];

    for (const fileName of expectedFiles) {
      expect(fs.existsSync(path.join(annotationsDir, fileName))).toBe(true);
    }
  });

  test('task2 customthings annotations expose core DarkRP APIs and aliases', () => {
    const customthingsLua = path.join(
      process.cwd(),
      'plugin',
      'darkrp',
      'annotations',
      'darkrp-customthings.lua',
    );

    expect(fs.existsSync(customthingsLua)).toBe(true);

    const content = fs.readFileSync(customthingsLua, 'utf8');
    expect(content).toMatch(/^\s*function\s+DarkRP\.createJob\s*\(/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.createShipment\s*\(/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.createAmmoType\s*\(\s*ammoType\s*,\s*tbl\s*\)/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.createVehicle\s*\(\s*tbl\s*\)/m);
    expect(content).not.toMatch(/^\s*function\s+DarkRP\.createVehicle\s*\(\s*name\s*,\s*tbl\s*\)/m);
    expect(content).toMatch(/---@overload\s+fun\(name:\s*string,\s*model:\s*string,\s*energy:\s*integer,\s*price:\s*integer\)/);
    expect(content).toMatch(/---@overload\s+fun\(name:\s*string,\s*color:\s*Color,/);
    expect(content).toMatch(/---@field\s+allowPurchaseWhileDead\?\s+boolean/);
    expect(content).toMatch(/---@field\s+onEaten\?\s+fun\(ply:\s*Player\)/);
    expect(content).toMatch(/---@field\s+customCheckMessage\?\s+string/);
    expect(content).toMatch(/^\s*(?:_G\.)?AddExtraTeam\s*=\s*DarkRP\.createJob\s*$/m);
    expect(content).toMatch(/^\s*RPExtraTeams\s*=/m);
    expect(content).toMatch(/^\s*CustomShipments\s*=/m);
    expect(content).toMatch(/^\s*DarkRPEntities\s*=/m);
    expect(content).not.toMatch(/---@return\s+DarkRPShipmentDefinition/);
    expect(content).not.toMatch(/---@return\s+DarkRPEntityDefinition/);
    expect(content).not.toMatch(/---@return\s+DarkRPAmmoDefinition/);
    expect(content).not.toMatch(/---@return\s+DarkRPVehicleDefinition/);
    expect(content).not.toMatch(/---@return\s+DarkRPFoodDefinition/);
  });

  test('task2 config annotations expose core surfaces', () => {
    const configLua = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations', 'darkrp-config.lua');

    expect(fs.existsSync(configLua)).toBe(true);

    const configContent = fs.readFileSync(configLua, 'utf8');

    expect(configContent).toMatch(/^\s*DarkRP\.disabledDefaults\s*=/m);
    expect(configContent).toMatch(/^\s*(?:GM|GAMEMODE)\.Config\.CategoryOverride\s*=/m);
  });

  test('task2 darkrp core helper signatures are compatible', () => {
    const coreLua = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations', 'darkrp.lua');

    expect(fs.existsSync(coreLua)).toBe(true);

    const content = fs.readFileSync(coreLua, 'utf8');
    expect(content).toMatch(/^\s*function\s+DarkRP\.getPhrase\s*\(\s*name\s*,\s*\.\.\.\s*\)/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.deLocalise\s*\(\s*text\s*\)/m);
    expect(content).toMatch(/^\s*function\s+DarkRP\.getPhraseLocalized\s*\(\s*ply\s*,\s*name\s*,\s*\.\.\.\s*\)/m);
    expect(content).not.toMatch(/^\s*function\s+DarkRP\.getPlayerVar\s*\(/m);
  });

});
