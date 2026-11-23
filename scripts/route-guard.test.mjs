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
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/models/RouteGuard.ets'), 'utf8');
const context = vm.createContext({
  exports: {},
  console: { warn() {}, error() {} }
});
const compilerOptions = { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS };
vm.runInContext(ts.transpileModule(source, { compilerOptions }).outputText, context);
const { isAllowedDirectAddress, shouldTryPlaintextBootstrap } = context.exports;

const cases = [
  ['68.183.234.72', true],
  ['0.0.0.0', true],
  ['255.255.255.255', true],
  ['::1', true],
  ['2001:db8::1', true],
  ['fe80::', true],
  ['::', true],
  ['1:2:3:4:5:6:7:8', true],
  ['evil.com', false],
  ['1.2.3.4:443', false],
  ['https://x', false],
  ['', false],
  ['999.1.1.1', false],
  ['1.2.3', false],
  ['1.2.3.4.5', false],
  ['[::1]', false],
  ['1.2.3.4 x', false],
  [':::', false],
  ['2001:db8::1::2', false],
  ['1:2:3:4:5:6:7:8:9', false],
  ['1'.repeat(46), false]
];

for (const [value, expected] of cases) {
  test(`${JSON.stringify(value)} is ${expected ? 'allowed' : 'rejected'}`, () => {
    assert.equal(isAllowedDirectAddress(value), expected);
  });
}

const bootstrapNow = 1_700_000_000_000;

test('plaintext bootstrap is disabled until the pool is exhausted', () => {
  assert.equal(shouldTryPlaintextBootstrap(false, 0, bootstrapNow), false);
  assert.equal(shouldTryPlaintextBootstrap(false, bootstrapNow - 31 * 60 * 1000, bootstrapNow), false);
});

test('plaintext bootstrap is allowed when no previous attempt exists', () => {
  assert.equal(shouldTryPlaintextBootstrap(true, 0, bootstrapNow), true);
});

test('plaintext bootstrap is rate limited before thirty minutes', () => {
  assert.equal(shouldTryPlaintextBootstrap(true, bootstrapNow - 29 * 60 * 1000, bootstrapNow), false);
});

test('plaintext bootstrap is allowed after thirty minutes', () => {
  assert.equal(shouldTryPlaintextBootstrap(true, bootstrapNow - 31 * 60 * 1000, bootstrapNow), true);
});

test('plaintext bootstrap is allowed at the thirty-minute boundary', () => {
  assert.equal(shouldTryPlaintextBootstrap(true, bootstrapNow - 30 * 60 * 1000, bootstrapNow), true);
});

const routeSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/network/ApiRouteManager.ets'), 'utf8');
const routeScript = new vm.Script(ts.transpileModule(routeSource, { compilerOptions }).outputText);
const defaultAddress = '192.0.2.10';
const addedAddress = '203.0.113.21';
const initHost = '198.51.100.8';
const httpsInit = 'https://' + initHost + '/init';
const httpInit = 'http://' + initHost + '/init';
const cooldown = 30 * 60 * 1000;

function initResponse(addresses) {
  return { responseCode: 200, result: JSON.stringify({ addresses }) };
}

function createRouteFixture(responses) {
  let now = bootstrapNow;
  let destroyed = 0;
  const requests = [];
  const networkKit = {
    http: {
      RequestMethod: { GET: 'GET' },
      HttpDataType: { STRING: 'string' },
      createHttp() {
        return {
          async request(url) {
            requests.push(url);
            return responses[url];
          },
          destroy() {
            destroyed++;
          }
        };
      }
    }
  };
  const modules = {
    '@kit.NetworkKit': networkKit,
    '../common/ImageLoader': {},
    '../common/Constants': { BIKA_INIT_HOST: initHost, BIKA_FALLBACK_IPS: [defaultAddress] },
    '../models/RouteGuard': context.exports
  };
  const runtime = {
    exports: {},
    require: (name) => modules[name],
    Date: { now: () => now },
    console: { info() {}, warn() {} }
  };
  routeScript.runInNewContext(runtime);
  const manager = runtime.exports.ApiRouteManager.getInstance();
  manager.probeEgressIp = () => {};
  return {
    manager,
    requests,
    get destroyed() { return destroyed; },
    advance(milliseconds) { now += milliseconds; },
    async refresh() {
      manager.forceRefresh();
      await manager.refreshPromise;
    },
    candidates() {
      return Array.from(manager.getCandidates());
    }
  };
}

test('HTTP bootstrap merges only valid new addresses in returned order', async () => {
  const fixture = createRouteFixture({
    [httpsInit]: { responseCode: 503 },
    [httpInit]: initResponse([defaultAddress, addedAddress, 'example.invalid', null, '2001:db8::8',
      addedAddress, 'https://example.invalid', '192.0.2.3:443'])
  });
  fixture.manager.notifyCandidatesExhausted();

  await fixture.refresh();

  assert.deepEqual(fixture.requests, [httpsInit, httpInit]);
  assert.deepEqual(fixture.candidates(), [defaultAddress, addedAddress, '2001:db8::8']);
  assert.equal(fixture.destroyed, 2);
});

test('valid HTTPS bootstrap takes precedence even after pool exhaustion', async () => {
  const fixture = createRouteFixture({
    [httpsInit]: initResponse([addedAddress]),
    [httpInit]: initResponse(['2001:db8::8'])
  });
  fixture.manager.notifyCandidatesExhausted();

  await fixture.refresh();

  assert.deepEqual(fixture.requests, [httpsInit]);
  assert.deepEqual(fixture.candidates(), [defaultAddress, addedAddress]);
});

test('HTTPS with no usable addresses still permits an eligible HTTP bootstrap', async () => {
  const fixture = createRouteFixture({
    [httpsInit]: initResponse(['example.invalid']),
    [httpInit]: initResponse([addedAddress])
  });
  fixture.manager.notifyCandidatesExhausted();

  await fixture.refresh();

  assert.deepEqual(fixture.requests, [httpsInit, httpInit]);
  assert.deepEqual(fixture.candidates(), [defaultAddress, addedAddress]);
});

test('HTTP bootstrap is skipped while there are still direct candidates to try', async () => {
  const fixture = createRouteFixture({
    [httpsInit]: { responseCode: 503 },
    [httpInit]: initResponse([addedAddress])
  });

  await fixture.refresh();

  assert.deepEqual(fixture.requests, [httpsInit]);
  assert.deepEqual(fixture.candidates(), [defaultAddress]);
});

test('an unusable HTTP response leaves the pool exhausted and starts the cooldown', async () => {
  const responses = {
    [httpsInit]: { responseCode: 503 },
    [httpInit]: { responseCode: 200, result: '{' }
  };
  const fixture = createRouteFixture(responses);
  fixture.manager.notifyCandidatesExhausted();

  await fixture.refresh();
  assert.deepEqual(fixture.candidates(), [defaultAddress]);

  responses[httpInit] = initResponse([addedAddress]);
  fixture.advance(cooldown - 1);
  await fixture.refresh();
  assert.deepEqual(fixture.requests, [httpsInit, httpInit, httpsInit]);
  assert.deepEqual(fixture.candidates(), [defaultAddress]);

  fixture.advance(1);
  await fixture.refresh();
  assert.deepEqual(fixture.requests, [httpsInit, httpInit, httpsInit, httpsInit, httpInit]);
  assert.deepEqual(fixture.candidates(), [defaultAddress, addedAddress]);
});
