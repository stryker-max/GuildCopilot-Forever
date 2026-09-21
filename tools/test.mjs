import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import JSZip from 'jszip';
import { root, source, addonName, files, packageAddon } from './package.mjs';
const toc = readFileSync(join(source, addonName + '.toc'), 'utf8');
assert.match(toc, /^## Interface: 16001$/m);
assert.match(toc, /^## Title: Guild Copilot$/m);
assert.match(toc, /^## SavedVariables: GuildCopilotForeverDB$/m);
const version = toc.match(/^## Version: (.+)$/m)[1].trim();
assert.equal(version, JSON.parse(readFileSync(join(root, 'package.json'))).version);
assert.ok(readFileSync(join(source, 'Constants.lua'), 'utf8').includes(`VERSION = "${version}"`));
const tocFiles = toc.split(/\r?\n/).map(x => x.trim()).filter(x => x && !x.startsWith('#'));
assert.equal(new Set(tocFiles).size, tocFiles.length);
for (const file of tocFiles) assert.ok(files(source).includes(file), 'Missing TOC file ' + file);
assert.ok(tocFiles.indexOf('Client.lua') < tocFiles.indexOf('Constants.lua'));
assert.ok(tocFiles.indexOf('ClientData.lua') < tocFiles.indexOf('Database.lua'));
assert.ok(!tocFiles.includes('WarcraftLogs.lua'));
for (const file of files(source).filter(x => x.endsWith('.lua'))) {
  const code = readFileSync(join(source, file), 'utf8');
  assert.ok(!/\bGuildCopilotDB\b|_G\.GuildCopilot\b/.test(code), 'TBC global leaked in ' + file);
  assert.ok(!code.includes('AddOns\\GuildCopilot\\'), 'TBC media path leaked in ' + file);
}
assert.ok(!files(join(root, '.github')).some(x => /curseforge/i.test(x)), 'TBC publishing workflow copied');
const first = await packageAddon();
const zip = await JSZip.loadAsync(readFileSync(first.archive));
const actual = Object.keys(zip.files).filter(x => !zip.files[x].dir).sort();
const expected = [...files(source).map(x => addonName + '/' + x), addonName + '/LICENSE'].sort();
assert.deepEqual(actual, expected);
for (const file of files(source)) {
  assert.deepEqual(await zip.file(addonName + '/' + file).async('nodebuffer'), readFileSync(join(source, file)));
}
const firstBytes = readFileSync(first.archive);
const second = await packageAddon();
assert.deepEqual(readFileSync(second.archive), firstBytes, 'Package is not reproducible');
const result = spawnSync(process.execPath, ['tools/run-lua-tests.mjs'], { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
assert.equal(result.status, 0, 'Lua suite failed');
console.log('All Forever source, package, isolation and API contract checks passed.');
