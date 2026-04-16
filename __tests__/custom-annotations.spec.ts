import fs from 'fs';
import path from 'path';

describe('custom and plugin annotation smoke checks', () => {
  test('darkrp plugin annotation files exist and are scoped', () => {
    const darkrpLua = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations', 'darkrp.lua');
    const camiLua = path.join(process.cwd(), 'plugin', 'darkrp', 'annotations', 'cami.lua');

    expect(fs.existsSync(darkrpLua)).toBe(true);
    expect(fs.existsSync(camiLua)).toBe(true);

    const darkrpContent = fs.readFileSync(darkrpLua, 'utf8');
    const camiContent = fs.readFileSync(camiLua, 'utf8');

    expect(darkrpContent).toContain('---@meta');
    expect(darkrpContent).toMatch(/DarkRP/);
    expect(camiContent).toContain('---@meta');
    expect(camiContent).toMatch(/CAMI/);
  });

  test('new custom class overrides and global alias are present', () => {
    const customRoot = path.join(process.cwd(), 'custom');
    const globals = fs.readFileSync(path.join(customRoot, '_globals.lua'), 'utf8');
    const dCheckBoxLabel = fs.readFileSync(path.join(customRoot, 'class.DCheckBoxLabel.lua'), 'utf8');
    const dHtmlControls = fs.readFileSync(path.join(customRoot, 'class.DHTMLControls.lua'), 'utf8');
    const dPanelList = fs.readFileSync(path.join(customRoot, 'class.DPanelList.lua'), 'utf8');

    expect(globals).toMatch(/---@alias GPlayer Player/);

    expect(dCheckBoxLabel).toMatch(/---@class DCheckBoxLabel : Panel/);
    expect(dCheckBoxLabel).toMatch(/---@field Button DCheckBox/);
    expect(dCheckBoxLabel).toMatch(/---@field Label DLabel/);

    expect(dHtmlControls).toMatch(/---@class DHTMLControls : Panel/);
    expect(dHtmlControls).toMatch(/---@field AddressBar DTextEntry/);

    expect(dPanelList).toMatch(/---@class DPanelList : DPanel/);
    expect(dPanelList).toMatch(/---@field Items Panel\[]/);
  });
});
