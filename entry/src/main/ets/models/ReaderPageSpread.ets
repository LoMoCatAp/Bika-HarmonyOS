export type ReaderPageLayout = 'auto' | 'single' | 'double';

/** 一次翻页显示的原始图片；始终以原始下标记录进度和拖拽对象。 */
export interface ReaderPageSpread {
  first: number;
  last: number;
  key: string;
}

export function normalizeReaderPageLayout(value: string): ReaderPageLayout {
  return value === 'single' || value === 'double' ? value : 'auto';
}

export function useReaderDoublePage(mode: number, layout: ReaderPageLayout, width: number, height: number): boolean {
  if (!Number.isInteger(mode) || mode > 2 || mode < 0 || layout === 'single') {
    return false;
  }
  if (layout === 'double') {
    return true;
  }
  // 按当前窗口的可用 vp 判断；窄分屏和横向小窗也需要足够的单页宽度。
  return Number.isFinite(width) && Number.isFinite(height) && width >= 720 && height > 0 && width / height >= 1.2;
}

export function normalizeReaderStripWidth(value: string): number {
  const width = Number(value);
  return Number.isFinite(width) && width >= 480 && width <= 1200 ? Math.round(width / 20) * 20 : 780;
}

export function isReaderWideImage(width: number, height: number): boolean {
  return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0 && width / height > 1.1;
}

export function buildReaderPageSpreads(count: number, doublePage: boolean, firstSingle: boolean,
  widePages: Set<number>): ReaderPageSpread[] {
  if (!Number.isSafeInteger(count) || count <= 0) {
    return [];
  }
  const spreads: ReaderPageSpread[] = [];
  for (let first = 0; first < count;) {
    const paired = doublePage && !(firstSingle && first === 0) && !widePages.has(first)
      && first + 1 < count && !widePages.has(first + 1);
    const last = paired ? first + 1 : first;
    spreads.push({ first: first, last: last, key: first + ':' + last });
    first = last + 1;
  }
  return spreads;
}

export function readerSpreadIndex(spreads: ReaderPageSpread[], page: number): number {
  if (spreads.length === 0) {
    return 0;
  }
  const target = Number.isFinite(page) ? Math.max(0, Math.floor(page)) : 0;
  const found = spreads.findIndex((spread: ReaderPageSpread): boolean => spread.first <= target && target <= spread.last);
  return found < 0 ? spreads.length - 1 : found;
}

export function readerSpreadPages(spread: ReaderPageSpread, rtl: boolean): number[] {
  if (spread.first === spread.last) {
    return [spread.first];
  }
  return rtl ? [spread.last, spread.first] : [spread.first, spread.last];
}

export function adjacentReaderSpreadPage(spreads: ReaderPageSpread[], page: number, delta: number): number {
  const next = readerSpreadIndex(spreads, page) + delta;
  return next >= 0 && next < spreads.length ? spreads[next].first : -1;
}

export function readerPageRange(spreads: ReaderPageSpread[], page: number, count: number): string {
  if (!Number.isSafeInteger(count) || count <= 0) {
    return '0 / 0';
  }
  const spread = spreads[readerSpreadIndex(spreads, page)];
  const start = spread?.first ?? (Number.isFinite(page) ? Math.min(count - 1, Math.max(0, Math.floor(page))) : 0);
  const end = spread?.last ?? start;
  return (start === end ? String(start + 1) : (start + 1) + '–' + (end + 1)) + ' / ' + count;
}
