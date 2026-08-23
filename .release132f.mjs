import { readFileSync } from 'node:fs';

const token = process.env.GH_TOKEN;
if (!token) {
  console.error('no token');
  process.exit(1);
}
const owner = 'LoMoCatAp';
const repo = 'Bika-HarmonyOS';
const base = 'https://api.github.com/repos/' + owner + '/' + repo;
const headers = {
  'Authorization': 'Bearer ' + token,
  'Accept': 'application/vnd.github+json',
  'User-Agent': 'bika-release',
  'X-GitHub-Api-Version': '2022-11-28'
};
const relRes = await fetch(base + '/releases/tags/v1.3.2', { headers });
if (relRes.status !== 200) {
  console.error('release not found', relRes.status);
  process.exit(1);
}
const rel = await relRes.json();
const assetsRes = await fetch(base + '/releases/' + rel.id + '/assets', { headers });
const assets = await assetsRes.json();
for (const a of assets) {
  if (a.name === 'entry-default-unsigned.hap') {
    const del = await fetch(base + '/releases/assets/' + a.id, { method: 'DELETE', headers });
    console.log('deleted old asset:', del.status);
  }
}
const buf = readFileSync('entry/build/default/outputs/default/entry-default-unsigned.hap');
const uploadUrl = 'https://uploads.github.com/repos/' + owner + '/' + repo + '/releases/' + rel.id + '/assets?name=entry-default-unsigned.hap';
const upRes = await fetch(uploadUrl, {
  method: 'POST',
  headers: { ...headers, 'Content-Type': 'application/octet-stream' },
  body: buf
});
console.log('new asset:', upRes.status);
if (upRes.status !== 201) {
  console.error(await upRes.text());
}
console.log('done');
