/** 纸面范围均为当前阅读窗口的 px，纹理始终使用整张原始快照的 UV。 */
export interface ReaderPaperRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface ReaderPaperParameters {
  width: number;
  height: number;
  frontRect: ReaderPaperRect;
  backRect: ReaderPaperRect;
  paired: boolean;
  fromRight: boolean;
  touchX: number;
  touchY: number;
  cornerY: number;
}

export interface ReaderCurlSurface {
  vertices: number[];
}

export interface ReaderSpineMesh {
  columns: number;
  rows: number;
  front: ReaderCurlSurface;
  back: ReaderCurlSurface;
}

export function validReaderPaperRect(rect: ReaderPaperRect): boolean {
  return Number.isFinite(rect.left) && Number.isFinite(rect.top) && Number.isFinite(rect.right)
    && Number.isFinite(rect.bottom) && rect.right > rect.left && rect.bottom > rect.top;
}

/** 与 NetImage 的 Contain 及中缝对齐规则一致，不把窗口留白变成翻起的纸张。 */
export function readerPaperImageRect(width: number, height: number, leftInset: number, rightInset: number,
  count: number, position: number, ratio: number): ReaderPaperRect {
  const cell = Math.max(1, (width - leftInset - rightInset - (count === 2 ? 2 : 0)) / count);
  const x = leftInset + position * (cell + (count === 2 ? 2 : 0));
  const imageWidth = Number.isFinite(ratio) && ratio > 0 ? Math.min(cell, height * ratio) : cell;
  const imageHeight = Number.isFinite(ratio) && ratio > 0 ? Math.min(height, cell / ratio) : height;
  const left = x + (count === 1 ? (cell - imageWidth) / 2 : (position === 0 ? cell - imageWidth : 0));
  return { left, top: (height - imageHeight) / 2, right: left + imageWidth, bottom: (height + imageHeight) / 2 };
}

interface PaperFoldGeometry {
  width: number;
  height: number;
  origin: number;
  top: number;
  direction: number;
  anchor: number;
  normalX: number;
  normalY: number;
  middleX: number;
  middleY: number;
  radius: number;
  halfArc: number;
  camera: number;
}

function paperFoldGeometry(p: ReaderPaperParameters): PaperFoldGeometry {
  const front = p.frontRect;
  const frontWidth = front.right - front.left;
  const frontHeight = front.bottom - front.top;
  const phase = Math.min(1, Math.max(0, (frontWidth - p.touchX) / (frontWidth * 2)));
  const blend = phase * phase * (3 - 2 * phase);
  const width = p.paired ? frontWidth + (p.backRect.right - p.backRect.left - frontWidth) * blend : frontWidth;
  const height = p.paired ? frontHeight + (p.backRect.bottom - p.backRect.top - frontHeight) * blend : frontHeight;
  const anchor = p.cornerY / frontHeight * height;
  const dx = Math.max(0.0001, 2 * phase * width);
  const middleX = (1 - phase) * width;
  const requestedY = (p.cornerY - p.touchY) / frontHeight * height;
  // 双页斜折必须留在书脊之外，否则中间那条边会被折线带起来。
  const maxY = dx * (p.paired ? Math.min(0.75, 0.55 * middleX / height) : 0.9);
  const dy = Math.max(-maxY, Math.min(maxY, requestedY));
  const distance = Math.hypot(dx, dy);
  const normalX = dx / distance;
  const normalY = dy / distance;
  const naturalRadius = Math.min(width, height) * 0.055 * Math.sin(Math.PI * phase);
  const radiusLimit = p.paired ? 0.8 * middleX * normalX / Math.PI : naturalRadius;
  const radius = Math.max(0.0001, Math.min(naturalRadius, radiusLimit));
  const origin = p.fromRight ? front.left : front.right;
  const destination = p.paired ? (p.fromRight ? p.backRect.right : p.backRect.left)
    : (p.fromRight ? 0 : p.width);
  return {
    width, height, origin: origin + (destination - origin) * blend,
    top: front.top + (p.paired ? p.backRect.top - front.top : 0) * blend,
    direction: p.fromRight ? 1 : -1, anchor, normalX, normalY, middleX, middleY: anchor - dy / 2,
    radius, halfArc: Math.PI * radius / 2, camera: Math.max(width, height) * 8
  };
}

function paperSurface(p: ReaderPaperParameters, g: PaperFoldGeometry, back: boolean,
  columns: number, rows: number): ReaderCurlSurface {
  const texture = back && p.paired ? p.backRect : p.frontRect;
  const reverse = back && p.paired ? p.fromRight : !p.fromRight;
  const textureWidth = texture.right - texture.left;
  const textureHeight = texture.bottom - texture.top;
  const vertexCount = (columns + 1) * (rows + 1) * 2;
  const vertices: number[] = new Array<number>(vertexCount);
  const paperColumns: number[] = new Array<number>(columns + 1);
  for (let column = 0; column <= columns; column++) {
    const u = Math.min(1, Math.max(0, (p.width * column / columns - texture.left) / textureWidth));
    paperColumns[column] = (reverse ? 1 - u : u) * g.width;
  }
  let index = 0;
  const arcLength = g.halfArc * 2;
  for (let row = 0; row <= rows; row++) {
    const y = Math.min(1, Math.max(0, (p.height * row / rows - texture.top) / textureHeight)) * g.height;
    const rowDistance = (y - g.middleY) * g.normalY - g.middleX * g.normalX;
    for (const x of paperColumns) {
      const distance = x * g.normalX + rowDistance;
      // 前后两面共用折线。压合不可见的部分，保留完整位图的纹理坐标。
      const clip = back ? Math.max(0, -distance) : -Math.max(0, distance);
      const arc = distance + clip + g.halfArc;
      let move = clip;
      let perspective = 1;
      if (arc >= arcLength) {
        move += arcLength - 2 * arc;
        perspective = 1 / (1 - 2 * g.radius / g.camera);
      } else if (arc > 0) {
        const angle = arc / g.radius;
        move += g.radius * Math.sin(angle) - arc;
        perspective = 1 / (1 - g.radius * (1 - Math.cos(angle)) / g.camera);
      }
      vertices[index++] = g.origin + g.direction * (x + g.normalX * move) * perspective;
      vertices[index++] = g.top + g.anchor + (y + g.normalY * move - g.anchor) * perspective;
    }
  }
  return { vertices };
}

export function buildReaderPaperMesh(p: ReaderPaperParameters): ReaderSpineMesh | null {
  if (!Number.isFinite(p.width) || !Number.isFinite(p.height) || p.width <= 0 || p.height <= 0
    || !validReaderPaperRect(p.frontRect) || !validReaderPaperRect(p.backRect)
    || !Number.isFinite(p.touchX) || !Number.isFinite(p.touchY) || !Number.isFinite(p.cornerY)) {
    return null;
  }
  const geometry = paperFoldGeometry(p);
  const columns = 40;
  const rows = 28;
  return {
    columns, rows,
    front: paperSurface(p, geometry, false, columns, rows),
    back: paperSurface(p, geometry, true, columns, rows)
  };
}
