/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Geometry adapted from HarmonyOS_Samples/PageFlip, PageNodeController.ets.
 * Modified by Bika-HarmonyOS in 2026: pure, instance-scoped bitmap page geometry,
 * bounded corner motion, finite intersection handling and bidirectional gestures.
 */

export type ReaderTurnEffect = 'slide' | 'curl';

export interface ReaderCurlPoint {
  x: number;
  y: number;
}

export interface ReaderCurlGeometry {
  a: ReaderCurlPoint;
  b: ReaderCurlPoint;
  c: ReaderCurlPoint;
  d: ReaderCurlPoint;
  e: ReaderCurlPoint;
  f: ReaderCurlPoint;
  h: ReaderCurlPoint;
  i: ReaderCurlPoint;
  j: ReaderCurlPoint;
  k: ReaderCurlPoint;
}

export function normalizeReaderTurnEffect(value: string): ReaderTurnEffect {
  return value === 'curl' ? 'curl' : 'slide';
}

export function readerCurlTarget(index: number, count: number, offset: number, rtl: boolean): number {
  if (!Number.isInteger(index) || !Number.isInteger(count) || index < 0 || index >= count
    || !Number.isFinite(offset) || offset === 0) {
    return -1;
  }
  const delta = (offset < 0 ? 1 : -1) * (rtl ? -1 : 1);
  const target = index + delta;
  return target >= 0 && target < count ? target : -1;
}

export function readerCurlProgress(offset: number, width: number, initialOffset: number): number {
  if (!Number.isFinite(offset) || !Number.isFinite(width) || width <= 0) {
    return 0;
  }
  // 手指退回起点后不允许直接改成另一方向的翻页。
  return Math.min(1, Math.max(0, offset * Math.sign(initialOffset) / width));
}

export function shouldCommitReaderCurl(progress: number, initialOffset: number, velocity: number): boolean {
  const speed = Number.isFinite(velocity) ? velocity * Math.sign(initialOffset) : 0;
  if (!Number.isFinite(progress) || speed < -650) {
    return false;
  }
  return progress >= 0.28 || (progress >= 0.025 && speed >= 650);
}

function curlIntersection(a: ReaderCurlPoint, b: ReaderCurlPoint,
  c: ReaderCurlPoint, d: ReaderCurlPoint): ReaderCurlPoint {
  const denominator = (a.x - b.x) * (c.y - d.y) - (a.y - b.y) * (c.x - d.x);
  if (Math.abs(denominator) < 0.000001) {
    return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
  }
  const ab = a.x * b.y - a.y * b.x;
  const cd = c.x * d.y - c.y * d.x;
  return {
    x: (ab * (c.x - d.x) - (a.x - b.x) * cd) / denominator,
    y: (ab * (c.y - d.y) - (a.y - b.y) * cd) / denominator
  };
}

/** 统一在右侧书页坐标系计算；左翻由绘制层镜像，不改变图片或页码顺序。 */
export function buildReaderCurlGeometry(width: number, height: number, progress: number,
  anchorY: number): ReaderCurlGeometry | null {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0
    || !Number.isFinite(progress) || !Number.isFinite(anchorY)) {
    return null;
  }
  const p = Math.min(0.999, Math.max(0.001, progress));
  const top = anchorY < height / 2;
  const arc = Math.max(0.0001, Math.min(height * 0.35, width * 0.55) * Math.sin(Math.PI * p));
  const f: ReaderCurlPoint = { x: width, y: top ? 0 : height };
  const a: ReaderCurlPoint = { x: width * (1 - 2 * p), y: top ? arc : height - arc };
  const g: ReaderCurlPoint = { x: (a.x + f.x) / 2, y: (a.y + f.y) / 2 };
  const e: ReaderCurlPoint = { x: g.x - Math.pow(f.y - g.y, 2) / (f.x - g.x), y: f.y };
  const h: ReaderCurlPoint = { x: f.x, y: g.y - Math.pow(f.x - g.x, 2) / (f.y - g.y) };
  const c: ReaderCurlPoint = { x: e.x - (f.x - e.x) / 2, y: f.y };
  const j: ReaderCurlPoint = { x: f.x, y: h.y - (f.y - h.y) / 2 };
  const b = curlIntersection(a, e, c, j);
  const k = curlIntersection(a, h, c, j);
  const d: ReaderCurlPoint = { x: (c.x + 2 * e.x + b.x) / 4, y: (c.y + 2 * e.y + b.y) / 4 };
  const i: ReaderCurlPoint = { x: (j.x + 2 * h.x + k.x) / 4, y: (j.y + 2 * h.y + k.y) / 4 };
  return { a, b, c, d, e, f, h, i, j, k };
}
