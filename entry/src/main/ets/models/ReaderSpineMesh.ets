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
  colors: number[];
}

export interface ReaderSpineMesh {
  columns: number;
  rows: number;
  front: ReaderCurlSurface;
  back: ReaderCurlSurface;
}

interface PaperProjection {
  x: number;
  y: number;
  color: number;
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

function paperProjection(p: ReaderPaperParameters, sourceX: number, sourceY: number, back: boolean): PaperProjection {
  const front = p.frontRect;
  const texture = back && p.paired ? p.backRect : front;
  const frontWidth = front.right - front.left;
  const frontHeight = front.bottom - front.top;
  const phase = Math.min(1, Math.max(0, (frontWidth - p.touchX) / (frontWidth * 2)));
  const blend = phase * phase * (3 - 2 * phase);
  const backWidth = p.backRect.right - p.backRect.left;
  const backHeight = p.backRect.bottom - p.backRect.top;
  const width = p.paired ? frontWidth + (backWidth - frontWidth) * blend : frontWidth;
  const height = p.paired ? frontHeight + (backHeight - frontHeight) * blend : frontHeight;
  const sourceU = Math.min(1, Math.max(0, (sourceX - texture.left) / (texture.right - texture.left)));
  const sourceV = Math.min(1, Math.max(0, (sourceY - texture.top) / (texture.bottom - texture.top)));
  // 纹理正反面共用几何。背面取下一张纸的内侧，完成后文字仍为正向。
  const reversed = back && p.paired ? p.fromRight : !p.fromRight;
  let x = (reversed ? 1 - sourceU : sourceU) * width;
  let y = sourceV * height;
  const fy = p.cornerY / frontHeight * height;
  const ax = p.touchX / frontWidth * width;
  const ay = p.touchY / frontHeight * height;
  const dx = width - ax;
  const dy = fy - ay;
  const distance = Math.max(0.0001, Math.hypot(dx, dy));
  const nx = dx / distance;
  const ny = dy / distance;
  const mx = (width + ax) / 2;
  const my = (fy + ay) / 2;
  let d = (x - mx) * nx + (y - my) * ny;
  // 在同一折线收拢不可见的一面，保持网格连续，不在 CPU 端拆成窄条。
  const clipped = back ? Math.max(0, -d) : -Math.max(0, d);
  x += nx * clipped;
  y += ny * clipped;
  d += clipped;
  const radius = Math.max(0.0001, Math.min(width, height) * 0.055 * Math.sin(Math.PI * phase));
  const arc = Math.max(0, d + Math.PI * radius / 2);
  const angle = Math.min(Math.PI, arc / radius);
  const displacement = arc <= Math.PI * radius
    ? radius * Math.sin(angle) - arc : Math.PI * radius - 2 * arc;
  const depth = radius * (1 - Math.cos(angle));
  const perspective = 1 / (1 - depth / (Math.max(width, height) * 8));
  const px = (x + nx * displacement) * perspective;
  const py = fy + (y + ny * displacement - fy) * perspective;
  const currentOrigin = p.fromRight ? front.left : front.right;
  const destinationOrigin = p.paired ? (p.fromRight ? p.backRect.right : p.backRect.left)
    : (p.fromRight ? 0 : p.width);
  const origin = currentOrigin + (destinationOrigin - currentOrigin) * blend;
  const top = front.top + (p.paired ? p.backRect.top - front.top : 0) * blend;
  // 原图颜色只在弯折处轻微压暗；不覆盖灰色或米色的整面染色。
  const tone = 255 - Math.round(22 * Math.pow(Math.sin(angle), 2));
  return {
    x: origin + (p.fromRight ? px : -px), y: top + py,
    color: (0xFF000000 | (tone << 16) | (tone << 8) | tone) >>> 0
  };
}

function paperSurface(p: ReaderPaperParameters, back: boolean, columns: number, rows: number): ReaderCurlSurface {
  const vertices: number[] = [];
  const colors: number[] = [];
  for (let row = 0; row <= rows; row++) {
    for (let column = 0; column <= columns; column++) {
      const point = paperProjection(p, p.width * column / columns, p.height * row / rows, back);
      vertices.push(point.x, point.y);
      colors.push(point.color);
    }
  }
  return { vertices, colors };
}

export function buildReaderPaperMesh(p: ReaderPaperParameters): ReaderSpineMesh | null {
  if (!Number.isFinite(p.width) || !Number.isFinite(p.height) || p.width <= 0 || p.height <= 0
    || !validReaderPaperRect(p.frontRect) || !validReaderPaperRect(p.backRect)
    || !Number.isFinite(p.touchX) || !Number.isFinite(p.touchY) || !Number.isFinite(p.cornerY)) {
    return null;
  }
  const columns = 96;
  const rows = 64;
  return { columns, rows, front: paperSurface(p, false, columns, rows), back: paperSurface(p, true, columns, rows) };
}
