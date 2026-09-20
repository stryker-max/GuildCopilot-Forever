import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import JSZip from 'jszip';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const addonName = 'GuildCopilotForever';
export const source = join(root, addonName);
export const build = join(root, 'build');
export function files(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name, 'en')).flatMap(entry =>
    entry.isDirectory() ? files(join(dir, entry.name), prefix + entry.name + '/') : [prefix + entry.name]);
}
export async function packageAddon() {
  const toc = readFileSync(join(source, addonName + '.toc'), 'utf8');
  const version = toc.match(/^## Version: (.+)$/m)?.[1].trim();
  if (!/^\d+\.\d+\.\d+-beta\.\d+$/.test(version)) throw new Error('Invalid beta version');
  // Only this repository's generated build directory may be replaced.
  if (resolve(build) !== resolve(root, 'build') || dirname(build) !== root) throw new Error('Unsafe build path');
  rmSync(build, { recursive: true, force: true });
  const stage = join(build, 'stage', addonName);
  mkdirSync(stage, { recursive: true });
  const zip = new JSZip();
  const manifest = {};
  for (const file of files(source)) {
    if (!/\.(lua|toc|tga)$/.test(file)) throw new Error('Unexpected addon file: ' + file);
    const bytes = readFileSync(join(source, file));
    const dest = join(stage, file);
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, bytes);
    manifest[file] = createHash('sha256').update(bytes).digest('hex');
    zip.file(addonName + '/' + file, bytes, { date: new Date('2020-01-01T00:00:00Z') });
  }
  zip.file(addonName + '/LICENSE', readFileSync(join(root, 'LICENSE')), { date: new Date('2020-01-01T00:00:00Z') });
  const archive = join(build, `${addonName}-${version}.zip`);
  const bytes = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  writeFileSync(archive, bytes);
  writeFileSync(join(build, 'SHA256.json'), JSON.stringify({ version, archive: createHash('sha256').update(bytes).digest('hex'), files: manifest }, null, 2) + '\n');
  console.log(`Built ${addonName} ${version}: ${Object.keys(manifest).length} addon files`);
  return { archive, manifest, stage };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await packageAddon();
