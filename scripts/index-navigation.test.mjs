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
const read = file => fs.readFileSync(path.join(root, 'entry/src/main/ets', file), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
function evaluate(source, globals = {}, imports = {}) {
  const context = vm.createContext({ exports: {}, ...globals, require: name => {
    assert(name in imports, `Unexpected dependency ${name}`); return imports[name];
  }, console: { warn() {}, error() {}, info() {}, debug() {} } });
  vm.runInContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText, context);
  return context.exports;
}
function subject(file, name, names, globals) {
  const ast = ts.createSourceFile(file, read(file), ts.ScriptTarget.Latest, true, ts.ScriptKind.ETS);
  const owner = ast.statements.find(node => node.name?.getText(ast) === name);
  assert(owner, `${name} must exist`);
  const methods = names.map(name => {
    const member = owner.members.find(node => node.name?.getText(ast) === name);
    assert(member, `${name} must exist`); return member.getText(ast);
  });
  const { Subject } = evaluate(`export class Subject {\n${methods.join('\n')}\n}`, globals);
  return new Subject();
}
const navigationMethods = ['shouldShowTabBar', 'canSwipeRootTabs', 'applyTabBarVisibility', 'syncTabBarVisibility',
  'applyPendingTabsMaterial', 'onTabsMaterialChanged', 'onTabsAppear', 'onSubpageChanged', 'openChannel',
  'onPageHide', 'onPageShow', 'aboutToDisappear', 'openProfileSubpage'];
function navigation({ routeFails = false } = {}) {
  const frames = [], animations = [], routes = [], messages = [], storage = new Map(), tabs = [];
  const page = subject('pages/IndexPage.ets', 'IndexPage', navigationMethods, {
    HdsAnimationMode: { CLICK_ANIMATION: 'click' },
    router: { pushUrl: route => { routes.push(route); return routeFails ? Promise.reject(new Error('route failed')) : Promise.resolve(); } },
    showImmersiveToast: message => messages.push(message.message),
    AppStorage: { set: (key, value) => storage.set(key, value), setOrCreate: (key, value) => storage.set(key, value) },
    ApiService: { getInstance: () => ({ isLoggedIn: () => true }) },
    FollowUpdateManager: { getInstance: () => ({ checkForUpdates() {} }) }
  });
  Object.assign(page, { currentTab: 1, subpageOpen: false, tabsPageVisible: true, tabsNodeReady: true,
    tabsSyncGeneration: 0, lastTabBarVisible: undefined, channelOpening: false, channelNavigationGeneration: 0,
    animationsEnabled: true, appliedTabsMaterial: 'EXQUISITE', materialLevel: 'EXQUISITE', appliedTabsRevision: 1, materialRev: 1,
    tabsController: { applyShowAnimation: () => animations.push('show'), applyHideAnimation: () => animations.push('hide'),
      changeIndex: index => tabs.push(index) },
    getUIContext: () => ({ postFrameCallback: callback => frames.push(callback) }), consumeWidgetAction() {}, publishCurrentRoute() {} });
  return { page, frames, animations, routes, messages, storage, tabs,
    flush: () => { for (const callback of frames.splice(0)) callback.onFrame(0); } };
}
test('profile subpages disable horizontal root-tab switching while the home tab remains independent', () => {
  const h = navigation(); h.page.subpageOpen = true;
  assert.equal(h.page.canSwipeRootTabs(), false); assert.equal(h.page.shouldShowTabBar(), false);
  h.page.currentTab = 0; assert.equal(h.page.canSwipeRootTabs(), true); assert.equal(h.page.shouldShowTabBar(), true);
});
test('entering a subpage hides the bar immediately and returning restores it after a frame', () => {
  const h = navigation(); h.page.subpageOpen = true; h.page.onSubpageChanged();
  assert.deepEqual(h.animations, ['hide']); h.flush(); assert.deepEqual(h.animations, ['hide']);
  h.page.subpageOpen = false; h.page.onSubpageChanged(); assert.deepEqual(h.animations, ['hide']);
  h.flush(); assert.deepEqual(h.animations, ['hide', 'show']);
});
test('an obsolete queued show cannot re-open the bar after a subpage opens', () => {
  const h = navigation(); h.page.syncTabBarVisibility(true);
  h.page.subpageOpen = true; h.page.onSubpageChanged(); h.flush();
  assert.deepEqual(h.animations, ['hide']);
});
test('channel entry submits the hide animation before routing and returning restores the bar', () => {
  const h = navigation(); h.page.currentTab = 0; h.page.openChannel('最近更新', 'latest');
  assert.deepEqual(h.animations, ['hide']); assert.equal(h.routes.length, 0);
  h.flush(); assert.equal(h.routes.length, 1);
  assert.deepEqual(plain(h.routes[0]), { url: 'pages/ChannelListPage', params: { label: '最近更新', kind: 'latest' } });
  h.page.onPageHide(); h.flush(); assert.equal(h.page.shouldShowTabBar(), false);
  h.page.onPageShow(); h.flush(); assert.equal(h.page.channelOpening, false); assert.equal(h.animations.at(-1), 'show');
});
test('a failed channel route clears its guard and restores the bar', async () => {
  const h = navigation({ routeFails: true }); h.page.openChannel('频道', 'normal'); h.flush();
  await Promise.resolve(); h.flush();
  assert.equal(h.page.channelOpening, false); assert.equal(h.animations.at(-1), 'show'); assert.equal(h.messages.length, 1);
});
test('repeated taps cannot queue duplicate channel routes and disappearance cancels pending navigation', () => {
  const first = navigation(); first.page.openChannel('频道', 'normal'); first.page.openChannel('频道', 'normal'); first.flush();
  assert.equal(first.routes.length, 1);
  const second = navigation(); second.page.openChannel('频道', 'normal'); second.page.aboutToDisappear(); second.flush();
  assert.equal(second.routes.length, 0); assert.equal(second.page.tabsNodeReady, false);
});
test('disabling animations opens a channel immediately while keeping the navigation guard', () => {
  const h = navigation(); h.page.animationsEnabled = false; h.page.openChannel('频道', 'normal');
  assert.equal(h.routes.length, 1); assert.equal(h.page.channelOpening, true); assert.equal(h.animations[0], 'hide');
});
test('material changes do not rebuild tabs while a subpage is open and apply after returning', () => {
  const h = navigation(); h.page.subpageOpen = true; h.page.materialLevel = 'GENTLE'; h.page.materialRev = 2;
  h.page.onTabsMaterialChanged(); assert.equal(h.page.appliedTabsMaterial, 'EXQUISITE'); assert.equal(h.frames.length, 0);
  h.page.subpageOpen = false; h.page.onSubpageChanged(); h.flush();
  assert.equal(h.page.appliedTabsMaterial, 'GENTLE'); assert.equal(h.page.appliedTabsRevision, 2);
});
test('material changes are deferred during channel entry or while the root page is hidden', () => {
  for (const flag of ['channelOpening', 'tabsPageVisible']) {
    const h = navigation(); h.page[flag] = flag === 'channelOpening'; h.page.materialLevel = 'SMOOTH';
    assert.equal(h.page.applyPendingTabsMaterial(), false); assert.equal(h.page.appliedTabsMaterial, 'EXQUISITE');
    h.page.onPageShow(); assert.equal(h.page.appliedTabsMaterial, 'SMOOTH');
  }
});
test('an unready native controller can recover on appear instead of leaving the bar permanently missing', () => {
  const h = navigation(); const original = h.page.tabsController.applyShowAnimation;
  h.page.tabsController.applyShowAnimation = () => { throw new Error('not ready'); };
  h.page.applyTabBarVisibility(true); assert.equal(h.page.lastTabBarVisible, undefined);
  h.page.tabsController.applyShowAnimation = original; h.page.onTabsAppear(); h.flush();
  assert.equal(h.animations.at(-1), 'show'); assert.equal(h.page.lastTabBarVisible, true);
});
test('profile deep links still select the profile tab and consume each subpage signal once', () => {
  const h = navigation(); h.page.openProfileSubpage('settings');
  assert.deepEqual(h.tabs, [1]); assert.equal(h.storage.get('bika_active_tab'), 1);
  const signal = h.storage.get('bika_open_subpage'); assert.equal(JSON.parse(signal).name, 'settings');
  const timers = [], opened = [];
  const profile = subject('features/profile/ProfilePage.ets', 'ProfilePage', ['consumeSubpageSignal'], {
    setTimeout: (callback, delay) => { timers.push({ callback, delay }); }
  });
  Object.assign(profile, { subpageSignal: signal, lastSubpageSignalTs: 0, openSubpage: name => opened.push(name) });
  profile.consumeSubpageSignal(); profile.consumeSubpageSignal(); assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 160); timers[0].callback(); assert.deepEqual(opened, ['settings']);
  profile.subpageSignal = '{broken'; profile.consumeSubpageSignal(); assert.equal(timers.length, 1);
});

const models = evaluate(read('models/Comic.ets'), {}, { '../common/Constants': { IMAGE_HOST_POOL: ['https://images.test'] } });
const comic = id => ({ _id: id, title: id, author: '作者', categories: [], epsCount: 1, pagesCount: 1,
  totalViews: 0, totalLikes: 0, finished: false, thumb: { fileServer: 'https://images.test', path: id + '.jpg' } });
function favourites() {
  let account = 'account'; const pending = [], requests = [], messages = [];
  const cache = { getEmail: () => account };
  const page = subject('features/profile/ProfilePage.ets', 'ProfilePage', ['loadFavourites', 'onLoginStateChanged'], {
    CacheManager: { getInstanceIfReady: () => cache }, ComicViewModel: models.ComicViewModel,
    showImmersiveToast: value => messages.push(value.message)
  });
  Object.assign(page, { cache, favRequestId: 0, favSort: 'dd', favPage: 1, favComics: [], favHasMore: false,
    favLoading: false, isLoggedIn: true, visibleSubpage: 'favourites', loadProfile() {},
    apiService: { getFavourites: (sort, number) => { requests.push([sort, number]);
      return new Promise((resolve, reject) => pending.push({ resolve, reject })); } } });
  return { page, pending, requests, messages, setAccount: value => account = value };
}
test('favourites retain paging, deduplicate results, and keep the current page on request failure', async () => {
  const h = favourites(); const first = h.page.loadFavourites(true);
  h.pending.shift().resolve({ comics: [comic('1'), comic('1'), comic('2')], pages: 3 }); await first;
  assert.deepEqual(plain(h.page.favComics.map(item => item.id)), ['1', '2']); assert.equal(h.page.favHasMore, true);
  const second = h.page.loadFavourites(false); h.pending.shift().resolve({ comics: [comic('2'), comic('3')], pages: 3 }); await second;
  assert.equal(h.page.favPage, 2); assert.deepEqual(plain(h.page.favComics.map(item => item.id)), ['1', '2', '3']);
  const third = h.page.loadFavourites(false); h.pending.shift().reject(new Error('offline')); await third;
  assert.equal(h.page.favPage, 2); assert.equal(h.page.favComics.length, 3); assert.equal(h.page.favLoading, false);
});
test('rapid favourite sort changes cannot apply an older result or end a newer loading state', async () => {
  const h = favourites(); const first = h.page.loadFavourites(true); h.page.favSort = 'da';
  const second = h.page.loadFavourites(true); h.pending[0].resolve({ comics: [comic('old')], pages: 1 }); await first;
  assert.equal(h.page.favLoading, true); assert.equal(h.page.favComics.length, 0);
  h.pending[1].resolve({ comics: [comic('new')], pages: 1 }); await second;
  assert.deepEqual(plain(h.page.favComics.map(item => item.id)), ['new']); assert.equal(h.page.favLoading, false);
});
test('logout or account switching rejects delayed favourite results', async () => {
  for (const logout of [true, false]) {
    const h = favourites(); const request = h.page.loadFavourites(true);
    if (logout) { h.page.isLoggedIn = false; h.page.onLoginStateChanged(); } else h.setAccount('other');
    h.pending[0].resolve({ comics: [comic('private')], pages: 1 }); await request;
    assert.equal(h.page.favComics.length, 0); assert.equal(h.page.favHasMore, false);
  }
});
test('a delayed favourite failure does not show a toast on another subpage', async () => {
  const h = favourites(); const request = h.page.loadFavourites(true); h.page.visibleSubpage = 'settings';
  h.pending[0].reject(new Error('offline')); await request; assert.equal(h.messages.length, 0);
});
test('download list subscriptions use the same callback when the component disappears', () => {
  const listeners = new Set(), events = [];
  const page = subject('features/downloads/DownloadListView.ets', 'DownloadListView', ['cb', 'aboutToAppear', 'aboutToDisappear'], {
    DownloadManager: { getInstance: () => ({ subscribe: callback => { listeners.add(callback); callback([{ comicId: '1' }]); },
      unsubscribe: callback => { events.push(callback); listeners.delete(callback); } }) }
  });
  page.aboutToAppear(); assert.equal(page.tasks.length, 1); assert.equal(listeners.size, 1);
  page.aboutToDisappear(); assert.equal(events[0], page.cb); assert.equal(listeners.size, 0);
});
