import fs from 'node:fs';
import os from 'node:os';
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
const read = file => fs.readFileSync(path.join(root, 'entry/src/main/ets', file), 'utf8').replace(/\r\n/g, '\n');
const plain = value => JSON.parse(JSON.stringify(value));
function load(source, imports = {}, globals = {}) {
  const context = vm.createContext({ exports: {}, require: name => {
    if (!(name in imports)) throw new Error(`Unexpected import ${name}`);
    return imports[name];
  }, console: { warn() {}, error() {}, info() {}, debug() {} }, ...globals });
  vm.runInContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText, context);
  return context.exports;
}
const models = load(read('models/Comic.ets'), { '../common/Constants': { IMAGE_HOST_POOL: ['https://images.test'] } });
function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'bika-offline-detail-test-'));
  t.after(() => {
    assert.equal(path.dirname(path.resolve(directory)), path.resolve(os.tmpdir()));
    assert(path.basename(directory).startsWith('bika-offline-detail-test-'));
    fs.rmSync(directory, { recursive: true, force: true });
  });
  let shortWrite = false;
  const fileIo = { accessSync: fs.existsSync, readTextSync: file => fs.readFileSync(file, 'utf8'),
    statSync: fs.statSync, mkdirSync: (file, recursive) => fs.mkdirSync(file, { recursive }),
    openSync: file => ({ fd: fs.openSync(file, 'w') }), closeSync: file => fs.closeSync(file.fd),
    writeSync: (fd, text) => fs.writeSync(fd, shortWrite ? text.slice(0, 8) : text),
    renameSync: fs.renameSync, unlinkSync: fs.unlinkSync, OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 } };
  const { ComicDetailStore: store } = load(read('common/ComicDetailStore.ets'), {
    '@kit.CoreFileKit': { fileIo }, '../models/Comic': models
  });
  store.initialize(directory);
  return { store, directory, setShortWrite: value => shortWrite = value };
}
function detail(extra = {}) {
  return { _id: 'comic-1', title: '作品一', author: '作者', description: '离线简介', categories: ['分类'], tags: ['标签'],
    totalViews: '1234', totalLikes: '56', pagesCount: '300', epsCount: '7', finished: true,
    thumb: { fileServer: 'https://images.test', path: 'cover.jpg' }, isFavourite: true, isLiked: true, ...extra };
}
const chapter = order => ({ _id: `ep-${order}`, title: `第${order}话`, order });
function task(order, extra = {}) {
  return { comicId: 'comic-1', comicTitle: '旧下载作品', author: '旧作者', description: '旧简介', coverUrl: 'https://images.test/cover',
    coverLocal: '', chapterOrder: order, chapterTitle: `旧第${order}话`, status: 'completed', total: 10,
    dir: `/local/comic-1/${order}`, progress: 10, sizeBytes: 10, ...extra };
}

test('old downloads restore real sparse chapter orders, metadata and stable distinct keys', t => {
  const { store } = fixture(t);
  const tasks = [task(7), task(5), task(5), task(6, { status: 'failed' }), task(8, { comicId: 'other' })];
  const before = JSON.stringify(tasks);
  const local = store.resolve('comic-1', '路由标题', tasks);
  assert.equal(local.comic.title, '旧下载作品'); assert.equal(local.comic.description, '旧简介');
  assert.equal(local.detailComplete, false); assert.equal(local.chaptersComplete, false);
  assert.deepEqual(plain(local.chapters.map(item => item.order)), [5, 7]);
  assert.equal(new Set(local.chapters.map(item => item.id)).size, 2);
  assert.equal(JSON.stringify(tasks), before); assert.equal(local.comic.epsCount, 0);
});
test('metadata and a chapter directory larger than a preferences value survive store reload', t => {
  const { store, directory } = fixture(t);
  store.saveDetail('comic-1', detail());
  store.saveChapters('comic-1', Array.from({ length: 500 }, (_, index) => chapter(index + 1)));
  store.initialize(directory);
  const snapshot = store.load('comic-1');
  assert.equal(snapshot.chapters.length, 500); assert.equal(snapshot.chaptersComplete, true);
  assert.equal(snapshot.detail.totalViews, 1234); assert.equal(snapshot.detail.tags[0], '标签');
  const raw = fs.readFileSync(path.join(directory, 'bika_metadata/comic-1.json'), 'utf8');
  assert(Buffer.byteLength(raw) > 8192); assert(!raw.includes('isFavourite')); assert(!raw.includes('isLiked'));
});
test('detail and chapter snapshots merge independently without erasing the other half', t => {
  const { store } = fixture(t);
  store.saveChapters('comic-1', [chapter(1), chapter(2)]);
  assert.equal(store.load('comic-1').detail, null);
  store.saveDetail('comic-1', detail());
  store.saveDetail('comic-1', detail({ title: '新标题' }));
  assert.equal(store.load('comic-1').chapters.length, 2);
  store.saveChapters('comic-1', [chapter(1), chapter(2), chapter(3)]);
  assert.equal(store.load('comic-1').detail.title, '新标题');
});
test('existing local cover is preferred for display while remote metadata stays reusable for downloads', t => {
  const { store, directory } = fixture(t);
  const cover = path.join(directory, 'cover.jpg'); fs.writeFileSync(cover, 'image');
  store.saveDetail('comic-1', detail()); store.saveChapters('comic-1', [chapter(1), chapter(5)]);
  const local = store.resolve('comic-1', '', [task(5, { coverLocal: cover }), task(7)]);
  assert.equal(local.localCoverUrl, `file://${cover}`); assert(local.comic.coverUrl.startsWith('https://'));
  assert.deepEqual(plain(local.chapters.map(item => item.order)), [1, 5, 7]);
  assert.equal(local.chapters[1].id, 'ep-5');
});
test('damaged metadata falls back to downloads without deleting or modifying them', t => {
  const { store, directory } = fixture(t);
  fs.mkdirSync(path.join(directory, 'bika_metadata'));
  fs.writeFileSync(path.join(directory, 'bika_metadata/comic-1.json'), '{broken');
  assert.equal(store.resolve('comic-1', '', [task(5)]).comic.title, '旧下载作品');
  assert.equal(store.resolve('missing', '', []), null);
});
test('a short write retains the previous valid snapshot and removes only its temporary file', t => {
  const h = fixture(t); h.store.saveDetail('comic-1', detail()); h.setShortWrite(true);
  h.store.saveDetail('comic-1', detail({ title: '损坏写入' }));
  assert.equal(h.store.load('comic-1').detail.title, '作品一');
  assert(!fs.existsSync(path.join(h.directory, 'bika_metadata/comic-1.json.tmp')));
});

function section(source, start, end) {
  const from = source.indexOf(start); assert(from >= 0, start);
  const until = source.indexOf(end, from); assert(until > from, end);
  return source.slice(from, until);
}
function pageHarness(t, tasks = [], api = {}) {
  const h = fixture(t), messages = [], routes = [], writes = [];
  const manager = { getTasks: () => tasks.slice(), hasTask: (id, order) => tasks.find(item => item.comicId === id && item.chapterOrder === order) };
  const source = read('pages/ComicDetailPage.ets');
  const methods = section(source, '  private startReading()', '  private openMetadataSearch(')
    + section(source, '  loadReadStatus()', '  /** 收藏/点赞弹簧');
  const { Page } = load(`export class Page {\n${methods}\n}`, {}, {
    ComicDetailStore: h.store, ...models, DownloadManager: { getInstance: () => manager },
    showImmersiveToast: message => messages.push(message.message), router: { pushUrl: route => routes.push(route) }
  });
  const page = new Page(); let account = 'account';
  Object.assign(page, { comicId: 'comic-1', comicTitle: '路由标题', detailRequestId: 0, comic: null, chapters: [],
    recommendations: [], lastReadOrder: 0, isLoading: false, usingLocalDetail: false,
    cacheManager: { getEmail: () => account, getReadProgress: () => page.lastReadOrder, getReadChapters: () => [],
      getCachedUpdatedChapterOrders: () => [7], getUpdatedChapterOrders: () => { writes.push(true); return [7]; } },
    epDownloaded: order => manager.hasTask(page.comicId, order)?.status === 'completed',
    apiService: { getComicDetail: async id => {
      const value = await (api.getComicDetail ? api.getComicDetail(id) : Promise.reject(new Error('offline')));
      h.store.saveDetail(id, value); return value;
    }, getAllEps: async id => {
      const value = await (api.getAllEps ? api.getAllEps(id) : Promise.reject(new Error('offline')));
      h.store.saveChapters(id, value); return value;
    }, getRecommendationsFor: async () => [], getComics: async () => ({ comics: [] }) } });
  return { ...h, page, messages, routes, writes, manager, setAccount: value => account = value };
}
test('offline details render before requests finish, remain usable after failure and do not change update baselines', async t => {
  const h = pageHarness(t, [task(5), task(7)]);
  const request = h.page.loadDetail(); assert.equal(h.page.comic.title, '旧下载作品');
  await request; assert.equal(h.page.isLoading, false); assert.equal(h.page.usingLocalDetail, true);
  assert.deepEqual(plain(h.page.chapters.map(item => item.order)), [5, 7]); assert.equal(h.writes.length, 0);
  h.page.lastReadOrder = 3; h.page.startReading();
  assert.equal(h.routes[0].params.currentOrder, 5); assert.equal(h.routes[0].params.epsCount, 7);
  assert.deepEqual(plain(h.routes[0].params.localChapterOrders), [5, 7]); assert.equal(h.routes[0].params.offlineOnly, true);
  assert.equal(h.routes[0].params.localDir, '/local/comic-1/5');
  h.page.lastReadOrder = 7; h.page.startReading(); assert.equal(h.routes[1].params.currentOrder, 7);
});
test('a successful detail request survives a failed chapter request and is usable on the next offline visit', async t => {
  const h = pageHarness(t, [task(5)], { getComicDetail: async () => detail() });
  await h.page.loadDetail(); assert.equal(h.page.comic.title, '作品一'); assert.equal(h.page.chapters[0].order, 5);
  assert.equal(h.page.detailComplete, true); assert.equal(h.page.usingLocalDetail, true); assert.equal(h.writes.length, 0);
  h.page.apiService.getComicDetail = async () => { throw new Error('offline'); };
  await h.page.loadDetail(); assert.equal(h.page.comic.title, '作品一');
});
test('a successful directory survives a failed detail request and blocks offline opening of undownloaded chapters', async t => {
  const h = pageHarness(t, [task(5)], { getAllEps: async () => [chapter(1), chapter(5), chapter(7)] });
  await h.page.loadDetail(); assert.equal(h.page.chaptersComplete, true);
  h.page.onChapterClick(h.page.chapters[0]); assert.equal(h.routes.length, 0); assert.match(h.messages[0], /还没下载/);
  h.page.startReading(); assert.equal(h.routes[0].params.currentOrder, 5);
});
test('full network recovery replaces old metadata and reconciles updates only after both results are complete', async t => {
  const h = pageHarness(t, [task(5)], { getComicDetail: async () => detail(), getAllEps: async () => [chapter(1), chapter(5)] });
  await h.page.loadDetail(); assert.equal(h.page.usingLocalDetail, false); assert.equal(h.writes.length, 1);
  assert.equal(h.page.comic.title, '作品一'); assert.equal(h.page.chapters.length, 2);
});
test('no network and no local information yields a clear retry state rather than fake empty statistics', async t => {
  const h = pageHarness(t); await h.page.loadDetail(); assert.equal(h.page.comic, null);
  assert.equal(h.page.errorMsg, '加载失败，点按重试'); assert.equal(h.writes.length, 0);
});
test('late results cannot overwrite another comic or an account changed during the request', async t => {
  for (const switchAccount of [false, true]) {
    let finish; const pending = new Promise(resolve => finish = resolve);
    const h = pageHarness(t, [], { getComicDetail: () => pending });
    const request = h.page.loadDetail();
    if (switchAccount) h.setAccount('other'); else h.page.comicId = 'comic-2';
    finish(detail()); await request; assert.equal(h.page.comic, null); assert.equal(h.writes.length, 0);
  }
});
test('offline reader previous/next traverses only downloaded chapters and online navigation remains sequential', () => {
  const source = read('pages/ReaderPage.ets');
  const methods = section(source, '  private updateChapterButtons()', '  private onImageFailed(');
  const { Reader } = load(`export class Reader {\n${methods}\n}`, {}, { Edge: { Top: 0 } });
  const page = new Reader(); Object.assign(page, { currentOrder: 5, epsCount: 7, offlineOnly: true,
    localChapterOrders: [5, 7], persistPageIndex() {}, publishCurrentReading() {},
    scrollScroller: { scrollEdge() {} }, loadLocalChapter() {} });
  page.updateChapterButtons(); assert.equal(page.hasPrevChapter, false); assert.equal(page.hasNextChapter, true);
  page.goNextChapter(); assert.equal(page.currentOrder, 7); assert.equal(page.hasNextChapter, false);
  page.goNextChapter(); assert.equal(page.currentOrder, 7); page.goPrevChapter(); assert.equal(page.currentOrder, 5);
  page.offlineOnly = false; page.updateChapterButtons(); page.goNextChapter(); assert.equal(page.currentOrder, 6);
});

function requestHarness(body) {
  const source = read('network/ApiService.ets');
  const methods = section(source, '  private async request<T>(', '  private sleep(');
  const { ApiService } = load(`export class ApiService { static rateLimitUntil = 0;\n${methods}\n}`, {}, {
    ApiRouteManager: { getInstance: () => ({ ensureInitialized() {}, getCandidates: () => ['127.0.0.1'] }) },
    BikaSigner: { buildHeaders: async () => ({}) }, BikaRcpClient: { request: async () => ({ responseCode: 200, body: JSON.stringify(body) }) },
    ERROR_MESSAGES: { '1007': '数据不存在或已被删除' }, BIKA_API_BASE: 'https://api.test', BIKA_API_HOST: 'api.test'
  });
  const api = new ApiService(); Object.assign(api, { token: 'test', authMutationId: 0 }); return api;
}
test('malformed API envelopes never expose NaN in the error message', async () => {
  for (const body of [null, [], {}, { code: null }, { code: '' }, { code: 'not-a-number' }, { code: false }]) {
    await assert.rejects(requestHarness(body).request('comics/comic-1', 'GET', null, false), error =>
      error.message.includes('返回内容异常') && !error.message.includes('NaN'));
  }
});
test('numeric string success codes and existing friendly API errors retain their behavior', async () => {
  assert.deepEqual(plain(await requestHarness({ code: '200', data: { ok: true } }).request('comics/comic-1', 'GET', null, false)), { ok: true });
  await assert.rejects(requestHarness({ code: 1007 }).request('comics/comic-1', 'GET', null, false), /数据不存在或已被删除/);
});

function metadataApi(store, responses) {
  const methods = section(read('network/ApiService.ets'), '  async getComicDetail(', '  /**\n   * 切换点赞状态');
  const { Api } = load(`export class Api {\n${methods}\n}`, {}, { ComicDetailStore: store });
  const api = new Api(); api.request = async () => {
    const response = responses.shift(); if (response instanceof Error) throw response; return response;
  }; return api;
}
test('API pagination failure retains the previous complete directory rather than caching the first page', async t => {
  const { store } = fixture(t); store.saveChapters('comic-1', [chapter(5), chapter(7)]);
  const api = metadataApi(store, [{ eps: { docs: [chapter(1)], pages: '2' } }, new Error('offline')]);
  await assert.rejects(api.getAllEps('comic-1'), /offline/);
  assert.deepEqual(plain(store.load('comic-1').chapters.map(item => item.order)), [5, 7]);
});
test('successful API pagination persists the full directory and public details independently', async t => {
  const { store } = fixture(t);
  const api = metadataApi(store, [{ comic: detail() }, { eps: { docs: [chapter(1)], pages: '2' } },
    { eps: { docs: [chapter(2)], pages: 2 } }]);
  assert.equal((await api.getComicDetail('comic-1')).isFavourite, true);
  assert.equal((await api.getAllEps('comic-1')).length, 2);
  assert.equal(store.load('comic-1').detail.title, '作品一');
  assert.deepEqual(plain(store.load('comic-1').chapters.map(item => item.order)), [1, 2]);
});
test('malformed detail or directory responses cannot overwrite existing valid metadata', async t => {
  const { store } = fixture(t); store.saveDetail('comic-1', detail()); store.saveChapters('comic-1', [chapter(5)]);
  for (const response of [undefined, {}, { comic: detail({ _id: 'other' }) }]) {
    await assert.rejects(metadataApi(store, [response]).getComicDetail('comic-1'), /返回内容异常/);
  }
  for (const response of [undefined, {}, { eps: { docs: null, pages: 1 } },
    { eps: { docs: [null], pages: 1 } }, { eps: { docs: [chapter(1)], pages: 'invalid' } }]) {
    await assert.rejects(metadataApi(store, [response]).getAllEps('comic-1'), /返回内容异常/);
  }
  assert.equal(store.load('comic-1').detail.title, '作品一'); assert.equal(store.load('comic-1').chapters[0].order, 5);
});
test('offline update badge lookup reads existing state without changing chapter-count baselines', () => {
  const { CacheManager } = load(read('common/CacheManager.ets'), {
    '@kit.ArkData': { preferences: {} }, './CredentialStore': { CredentialStore: {} }
  });
  const saved = new Map([
    ['chapter_updates_comic-1', JSON.stringify({ epsCount: 7, pendingFromCount: -1,
      knownChapterIds: ['ep-5', 'ep-7'], chapters: [{ id: 'ep-5', order: 5 }, { id: 'ep-7', order: 7 }] })],
    ['read_chapters_comic-1', '[5]']
  ]); const writes = [];
  const cache = new CacheManager(); cache.prefs = { getSync: (key, fallback) => saved.get(key) ?? fallback,
    putSync: (...args) => writes.push(args), flushSync() {} };
  const before = JSON.stringify([...saved]);
  assert.deepEqual(plain(cache.getCachedUpdatedChapterOrders('comic-1')), [7]);
  assert.equal(writes.length, 0); assert.equal(JSON.stringify([...saved]), before);
});
