import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const studio = process.env.DEVECO_STUDIO_HOME || path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Huawei', 'DevEco Studio');
const ts = require(path.join(process.env.DEVECO_SDK_HOME || path.join(studio, 'sdk'),
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = process.env.BIKA_PROJECT_ROOT || fileURLToPath(new URL('../', import.meta.url));
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/common/CacheManager.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '');

const context = vm.createContext({
  exports: {},
  console: { warn() {}, error() {} }
});
vm.runInContext(ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
}).outputText, context);
const { isImageCacheKey } = context.exports;

test('chapter image cache key is accepted', () => {
  assert.equal(isImageCacheKey('chapter_1_2'), true);
});

test('chapter update state key is excluded', () => {
  assert.equal(isImageCacheKey('chapter_updates_1'), false);
});

test('comics cache key is accepted', () => {
  assert.equal(isImageCacheKey('comics_x'), true);
});

test('categories cache key is accepted', () => {
  assert.equal(isImageCacheKey('categories'), true);
});

test('unrelated setting key is excluded', () => {
  assert.equal(isImageCacheKey('setting_x'), false);
});

test('empty key is excluded', () => {
  assert.equal(isImageCacheKey(''), false);
});

test('chapter prefix alone is accepted', () => {
  assert.equal(isImageCacheKey('chapter_'), true);
});

test('chapter update prefix alone is excluded', () => {
  assert.equal(isImageCacheKey('chapter_updates_'), false);
});
