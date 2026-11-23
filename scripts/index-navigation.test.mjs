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
test('home channel columns fit the measured compact tablet and split-screen widths', () => {
  const source = ts.createSourceFile('Constants.ets', read('common/Constants.ets'), ts.ScriptTarget.Latest, true);
  const method = source.statements.find(node => node.name?.getText(source) === 'adaptiveChannelColumns');
  assert(method);
  const { adaptiveChannelColumns } = evaluate(method.getText(source));
  for (const [width, count] of [[0,3],[360,3],[459,3],[460,4],[530,4],[599,4],[600,5],[849,5],[850,6]]) {
    assert.equal(adaptiveChannelColumns(width).split(' ').length, count, 'width: ' + width);
  }
});

function materialHarness({ api = 26, hardware = true, componentHardware = hardware, disabled = false, failBuild = false } = {}) {
  const empty = {};
  const card = 'theme-card';
  const title = 'theme-text';
  let hardwareQueries = 0;
  const uiMaterial = {
    Material: { empty },
    MaterialState: { ENABLE: 1, DISABLE: 2 },
    ImmersiveStyle: { ULTRA_THIN: 0, THIN: 1, REGULAR: 2, THICK: 3, ULTRA_THICK: 4 },
    isImmersiveMaterialSupported: () => componentHardware,
    getMaterialInfo: () => ({ state: disabled ? 2 : 1 }),
    ImmersiveMaterial: class {
      constructor(options) {
        if (failBuild) throw new Error('material unavailable');
        this.options = options;
      }
    }
  };
  const storage = new Map([['bika_color_mode','dark']]);
  const globals = { Color: { Transparent: 'transparent' }, BlurStyle: { NONE: 0 },
    AppStorage: { get: key => storage.get(key) } };
  const materialStyle = evaluate(read('common/ImmersiveMaterialLevel.ets'), globals);
  const material = evaluate(read('common/CompatibleMaterial.ets'), globals, {
    '@kit.ArkUI': { CommonModifier: class {}, uiMaterial },
    '@kit.BasicServicesKit': { deviceInfo: { sdkApiVersion: api } },
    '@kit.UIDesignKit': { hdsMaterial: {
      MaterialType: { IMMERSIVE: 101 },
      getSystemMaterialTypes: () => { hardwareQueries++; return hardware ? [101] : []; }
    } },
    './Constants': { COLOR_CARD: card },
    './ImmersiveMaterialLevel': materialStyle
  });
  const popup = evaluate(read('common/ImmersiveToast.ets'), globals, {
    '@kit.ArkUI': { promptAction: { showToast() {}, showDialog: async options => options } },
    './CompatibleMaterial': material,
    './Constants': { COLOR_CARD: card, COLOR_TEXT_TITLE: title }
  });
  return { ...material, ...popup, ...materialStyle, storage, empty, card, title,
    get hardwareQueries() { return hardwareQueries; } };
}

test('legacy, unsupported and disabled material use opaque capsule and popup surfaces', async () => {
  for (const fixture of [{ api: 22 }, { hardware: false }, { disabled: true }]) {
    const h = materialHarness(fixture);
    assert.equal(h.supportsComponentImmersiveMaterial(), false);
    const sheet = h.compatibleSheetOptions({});
    const menu = h.compatibleMenuOptions({});
    const attributes = {};
    new h.GlassCapsuleMaterial(h.card).applyNormalAttribute({
      backgroundColor: color => { attributes.color = color; },
      systemMaterial: material => { attributes.material = material; }
    });
    const toast = { message: 'test' };
    h.showImmersiveToast(toast);
    const dialog = await h.showImmersiveDialog({});
    assert.equal(attributes.color, h.card);
    for (const options of [sheet, menu, toast, dialog]) {
      assert.equal(options.backgroundColor, h.card);
      assert.equal(options.systemMaterial, fixture.api ? undefined : h.empty);
    }
    assert.equal(sheet.blurStyle, 0);
    assert.equal(toast.textColor, h.title);
    if (fixture.api) assert.equal(h.hardwareQueries, 0);
  }
});

test('supported material keeps native styling and a failed material builds a solid sheet', () => {
  const supported = materialHarness();
  assert.equal(supported.supportsComponentImmersiveMaterial(), true);
  const sheet = supported.compatibleSheetOptions({});
  assert.equal(sheet.backgroundColor, undefined);
  assert.equal(sheet.systemMaterial.options.materialColor, '#B31B2029');
  assert.equal(supported.compatiblePopupMaterial().options.materialColor, undefined);
  assert.equal(supported.compatibleSheetOptions({ backgroundColor: 'reader' }, false).systemMaterial, supported.empty);
  const failing = materialHarness({ failBuild: true });
  const fallback = failing.compatibleSheetOptions({ backgroundColor: 'explicit' });
  assert.equal(fallback.backgroundColor, 'explicit');
  assert.equal(fallback.systemMaterial, failing.empty);
});

test('all five material thicknesses reach capsule, menu and popup constructors', () => {
  const h = materialHarness();
  for (const [style, expected] of ['ULTRA_THIN','THIN','REGULAR','THICK','ULTRA_THICK'].map((name,index) => [name,index])) {
    h.storage.set('bika_material_style',style);
    let applied;
    new h.GlassCapsuleMaterial(h.card).applyNormalAttribute({
      backgroundColor(){}, systemMaterial:material=>{applied=material;}
    });
    assert.equal(applied.options.style,expected);
    assert.equal(h.compatibleMenuOptions({}).systemMaterial.options.style,expected);
    assert.equal(h.compatibleSheetOptions({}).systemMaterial.options.style,expected);
    assert.equal(h.compatiblePopupMaterial().options.style,expected);
    assert.equal(h.immersiveCapsuleTint('GENTLE',false),'#33FFFFFF');
  }
  h.storage.delete('bika_material_style');
  assert.equal(h.compatiblePopupMaterial().options.style,1);
  h.storage.set('bika_material_style','old-invalid-value');
  assert.equal(h.compatiblePopupMaterial().options.style,1);
  assert.equal(h.normalizeMaterialStyle(''), 'THIN');
});

test('switching grade affects reopened popups and retains independently chosen thickness', async () => {
  const h = materialHarness();
  h.storage.set('bika_material_style', 'THICK');
  for (const [level, shadow, light] of [
    ['SMOOTH', false, null], ['EXQUISITE', true, '#FF7CA8'],
    ['GENTLE', false, '#66FF7CA8'], ['ADAPTIVE', undefined, undefined]
  ]) {
    h.storage.set('bika_material_level', level);
    const toast = { message: 'test' };
    h.showImmersiveToast(toast);
    const dialog = await h.showImmersiveDialog({});
    for (const popup of [toast, dialog, h.compatibleMenuOptions({}, 'THICK', level),
      h.compatibleSheetOptions({}, true, 'THICK', level)]) {
      const opts = popup.systemMaterial.options;
      assert.equal(opts.style, 3);
      assert.equal(opts.applyShadow, shadow);
      assert.equal(opts.lightEffect && opts.lightEffect.color, light);
    }
  }
});

test('both native material menus use the chosen grade and thickness', () => {
  // ArkUI capability and HDS capability must be queried independently.
  const h = materialHarness({ hardware: false, componentHardware: true });
  assert.equal(h.supportsHdsImmersiveMaterial(), false);
  for (const thickness of [true, false]) {
    const picker = subject('features/profile/MaterialLevelSelect.ets', 'MaterialLevelSelect', ['menuOptions'], h);
    Object.assign(picker, { thickness, colorMode: 'system', systemColorMode: 'dark', materialStyle: 'THICK' });
    for (const [grade, tint] of [['EXQUISITE', undefined], ['GENTLE', '#6620252E'],
      ['SMOOTH', '#D920252E'], ['ADAPTIVE', undefined]]) {
      picker.level = grade;
      const menu = picker.menuOptions();
      assert.equal(menu.systemMaterial.options.style, 3);
      assert.equal(menu.systemMaterial.options.materialColor, tint);
    }
    picker.level = 'SMOOTH';
    picker.systemColorMode = 'light';
    assert.equal(picker.menuOptions().systemMaterial.options.materialColor, '#D9FFFFFF');
  }
});

function materialSelector(thickness) {
  const options=evaluate(read('features/profile/ProfileOptions.ets'));
  const saved=new Map(), messages=[];
  const storage=new Map([['bika_animations',false],['bika_material_rev',2]]);
  let provider;
  const cache={isReady:()=>true,saveSetting:(key,value)=>saved.set(key,value)};
  provider=()=>Promise.resolve(cache);
  const page=subject('features/profile/MaterialLevelSelect.ets','MaterialLevelSelect',
    ['options','selectedIndex','label','select','aboutToDisappear'],{
      ...options,CacheManager:{getInstance:()=>provider()},showImmersiveToast:options=>messages.push(options.message),
      AppStorage:{get:key=>storage.get(key),setOrCreate:(key,value)=>storage.set(key,value)}
    });
  Object.assign(page,{thickness,level:'SMOOTH',materialStyle:'THIN',pendingValue:'',request:0});
  return {page,saved,storage,messages,cache,setProvider:value=>provider=value};
}

test('material selectors persist independent preferences while preserving the saved level',async()=>{
  const thickness=materialSelector(true);
  await thickness.page.select('ULTRA_THICK');
  assert.equal(thickness.saved.get('material_style'),'ULTRA_THICK');
  assert.equal(thickness.saved.has('material_level'),false);
  assert.equal(thickness.page.level,'SMOOTH');
  assert.equal(thickness.page.label(),'超厚');
  const grade=materialSelector(false);
  await grade.page.select('GENTLE');
  assert.equal(grade.saved.get('material_level'),'GENTLE');
  assert.equal(grade.page.materialStyle,'THIN');
  assert.equal(grade.storage.get('bika_material_rev'),3);
});

test('the selector shows a choice pending save and keeps it once saved', async () => {
  for (const [thickness, value, label] of [[false, 'GENTLE', '轻柔'], [true, 'ULTRA_THIN', '超薄']]) {
    const h = materialSelector(thickness);
    let resume;
    h.setProvider(() => new Promise(resolve => { resume = resolve; }));
    const pending = h.page.select(value);
    assert.equal(h.page.label(), label);
    assert.equal(h.saved.size, 0);
    resume(h.cache);
    await pending;
    assert.equal(h.saved.get(thickness ? 'material_style' : 'material_level'), value);
    assert.equal(h.page.label(), label);
    assert.equal(h.page.pendingValue, '');
  }
});

test('failed persistence keeps the active thickness and reports the failure',async()=>{
  for (const failure of ['not-ready','write-failed']) {
    const h=materialSelector(true);
    if(failure==='not-ready')h.cache.isReady=()=>false;
    else h.cache.saveSetting=()=>{throw new Error('write failed');};
    await h.page.select('THICK');
    assert.equal(h.page.materialStyle,'THIN');
    assert.equal(h.page.label(),'薄');
    assert.equal(h.saved.size,0);
    assert.deepEqual(h.messages,['显示设置保存失败，请重试']);
  }
});

test('latest material choice wins if settings load out of order, and leaving cancels pending writes',async()=>{
  const h=materialSelector(true),pending=[];
  h.setProvider(()=>new Promise(resolve=>pending.push(resolve)));
  const first=h.page.select('ULTRA_THIN');
  const second=h.page.select('THICK');
  pending[1](h.cache);
  await second;
  pending[0](h.cache);
  await first;
  assert.equal(h.saved.get('material_style'),'THICK');
  const leaving=h.page.select('REGULAR');
  h.page.aboutToDisappear();
  pending[2](h.cache);
  await leaving;
  assert.equal(h.saved.get('material_style'),'THICK');
});

const navigationMethods = ['shouldShowTabBar', 'canSwipeRootTabs', 'applyTabBarVisibility', 'syncTabBarVisibility',
  'applyPendingTabsMaterial', 'onTabsMaterialChanged', 'onTabsAppear', 'onSubpageChanged', 'openChannel',
  'tabsBackgroundEffect', 'hdsMaterialLevel',
  'onPageHide', 'onPageShow', 'aboutToDisappear', 'openProfileSubpage'];
function navigation({ routeFails = false } = {}) {
  const frames = [], animations = [], routes = [], messages = [], storage = new Map(), tabs = [];
  const page = subject('pages/IndexPage.ets', 'IndexPage', navigationMethods, {
    ...evaluate(read('common/ImmersiveMaterialLevel.ets')),
    COLOR_CARD: 'theme-card',
    hdsMaterial: { MaterialLevel: { EXQUISITE: 'exquisite', GENTLE: 'gentle', SMOOTH: 'smooth', ADAPTIVE: 'adaptive' } },
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
    appliedTabsStyle: 'THIN', materialStyle: 'THIN', immersiveTabs: true,
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
test('thickness alone reaches HDS on returning from settings without changing its native grade', () => {
  const h = navigation();
  h.page.subpageOpen = true;
  h.page.materialStyle = 'ULTRA_THICK';
  h.page.onTabsMaterialChanged();
  assert.equal(h.page.appliedTabsStyle, 'THIN');
  assert.equal(h.frames.length, 0);
  const thin = h.page.tabsBackgroundEffect();
  const grade = h.page.hdsMaterialLevel();
  h.page.subpageOpen = false;
  h.page.onSubpageChanged();
  h.flush();
  assert.equal(h.page.appliedTabsStyle, 'ULTRA_THICK');
  assert.equal(h.page.hdsMaterialLevel(), grade);
  assert.equal(h.page.appliedTabsRevision, 1);
  assert(h.page.tabsBackgroundEffect().radius > thin.radius);
  assert.equal(h.animations.at(-1), 'show');
  assert.equal(h.page.applyPendingTabsMaterial(), false);
  h.page.materialStyle = 'THIN';
  assert.equal(h.page.applyPendingTabsMaterial(), true);
  assert.deepEqual(plain(h.page.tabsBackgroundEffect()), plain(thin));
});
test('pending HDS thickness waits for channel navigation and uses the latest saved choice', () => {
  for (const flag of ['channelOpening', 'tabsPageVisible']) {
    const h = navigation();
    h.page[flag] = flag === 'channelOpening';
    for (const style of ['ULTRA_THICK', 'REGULAR']) {
      h.page.materialStyle = style;
      assert.equal(h.page.applyPendingTabsMaterial(), false);
      assert.equal(h.page.appliedTabsStyle, 'THIN');
    }
    h.page.onPageShow();
    h.flush();
    assert.equal(h.page.appliedTabsStyle, 'REGULAR');
    assert.equal(h.animations.at(-1), 'show');
  }
});
test('HDS thickness changes only blur radius and preserves the unsupported-device fallback', () => {
  const h = navigation();
  let lastRadius = -1;
  for (const style of ['ULTRA_THIN', 'THIN', 'REGULAR', 'THICK', 'ULTRA_THICK']) {
    h.page.materialStyle = style;
    h.page.applyPendingTabsMaterial();
    const effect = plain(h.page.tabsBackgroundEffect());
    assert.deepEqual(Object.keys(effect), ['radius']);
    if (style === 'ULTRA_THIN') assert.equal(effect.radius, 0);
    assert(effect.radius > lastRadius);
    lastRadius = effect.radius;
  }
  h.page.immersiveTabs = false;
  assert.deepEqual(plain(h.page.tabsBackgroundEffect()), { radius: 0, color: 'theme-card' });
  h.page.immersiveTabs = true;
  h.page.materialStyle = 'invalid-old-value';
  h.page.applyPendingTabsMaterial();
  assert.equal(h.page.appliedTabsStyle, 'THIN');
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
