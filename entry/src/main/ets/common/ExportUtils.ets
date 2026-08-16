import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';

/**
 * 导出工具：漫画图片 → PDF / ZIP 压缩包
 * - ZIP：STORE（无压缩）方式手写 ZIP 容器，图片本身已是 JPEG 压缩格式
 * - PDF：最小合法 PDF 生成器，每张图一页，JPEG 用 DCTDecode 直接嵌入
 * 输出到应用沙箱缓存目录，再由 SaveButton 安全控件授权导出到公共目录。
 */

/** UTF-8 编码文本 → 字节 */
function utf8(text: string): Uint8Array {
  let encoder = new util.TextEncoder();
  return encoder.encodeInto(text);
}

/** 拼接多个字节块 */
function concat(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let p of parts) {
    total += p.length;
  }
  let out = new Uint8Array(total);
  let offset = 0;
  for (let p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

/** 32 位小端写入 */
function u32le(value: number): Uint8Array {
  let out = new Uint8Array(4);
  out[0] = value & 0xFF;
  out[1] = (value >> 8) & 0xFF;
  out[2] = (value >> 16) & 0xFF;
  out[3] = (value >>> 24) & 0xFF;
  return out;
}

function u16le(value: number): Uint8Array {
  let out = new Uint8Array(2);
  out[0] = value & 0xFF;
  out[1] = (value >> 8) & 0xFF;
  return out;
}

/** CRC32（ZIP 校验用） */
class Crc32 {
  private static table: number[] = [];
  private static ready: boolean = false;

  private static ensureTable(): void {
    if (Crc32.ready) {
      return;
    }
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) {
        c = (c & 1) !== 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      Crc32.table.push(c >>> 0);
    }
    Crc32.ready = true;
  }

  static of(data: Uint8Array): number {
    Crc32.ensureTable();
    let c = 0xFFFFFFFF;
    for (let i = 0; i < data.length; i++) {
      c = Crc32.table[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) >>> 0;
  }
}

/** 图片尺寸 */
interface ImgSize {
  w: number;
  h: number;
}

/** PDF 对象 */
interface PdfObject {
  bytes: Uint8Array;
  offset: number;
}

const NEWLINE: string = '\n';

/** 当前章节图片 → ZIP（STORE 无压缩，文件名 001.jpg / 002.jpg …） */
export async function exportImagesZip(images: ArrayBuffer[], outPath: string, baseName: string): Promise<void> {
  let locals: Uint8Array[] = [];
  let centrals: Uint8Array[] = [];
  let count = 0;
  let index = 1;
  for (let buf of images) {
    let data = new Uint8Array(buf);
    let crc = Crc32.of(data);
    let name = baseName + '_' + String(index).padStart(3, '0') + '.jpg';
    let nameBytes = utf8(name);
    let nameLen = nameBytes.length;
    let local = concat([
      u32le(0x04034b50), u16le(20), u16le(0), u16le(0), u16le(0), u16le(0),
      u32le(crc), u32le(data.length), u32le(data.length), u16le(nameLen), u16le(0),
      nameBytes, data
    ]);
    locals.push(local);
    let central = concat([
      u32le(0x02014b50), u16le(20), u16le(20), u16le(0), u16le(0), u16le(0), u16le(0),
      u32le(crc), u32le(data.length), u32le(data.length), u16le(nameLen), u16le(0), u16le(0),
      u16le(0), u16le(0), u32le(0), u32le(0),
      nameBytes
    ]);
    centrals.push(central);
    count++;
    index++;
  }
  let centralSize = 0;
  for (let c of centrals) {
    centralSize += c.length;
  }
  let body = concat(locals);
  let centralDir = concat(centrals);
  let eocd = concat([
    u32le(0x06054b50), u16le(0), u16le(0), u16le(count), u16le(count),
    u32le(centralSize), u32le(body.length), u16le(0)
  ]);
  let zip = concat([body, centralDir, eocd]);
  let file = fs.openSync(outPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, zip.buffer as ArrayBuffer);
  fs.closeSync(file.fd);
}

/** 当前章节图片 → 单页 PDF（JPEG DCTDecode 直嵌） */
export async function exportImagesPdf(images: ArrayBuffer[], outPath: string, title: string): Promise<void> {
  let sizes: ImgSize[] = [];
  for (let buf of images) {
    try {
      let source = image.createImageSource(buf);
      let info = await source.getImageInfo();
      sizes.push({ w: info.size.width, h: info.size.height });
      source.release();
    } catch (err) {
      sizes.push({ w: 1080, h: 1440 });
    }
  }
  let kids: string[] = [];
  for (let i = 0; i < images.length; i++) {
    kids.push(String(3 + i * 3) + ' 0 R');
  }
  let catalog = utf8('<< /Type /Catalog /Pages 2 0 R >>');
  let pages = utf8('<< /Type /Pages /Kids [' + kids.join(' ') + '] /Count ' + images.length + ' >>');
  // 每页三个对象：Page / Image(XObject) / Contents(stream)
  let perPage: Uint8Array[][] = [];
  for (let i = 0; i < images.length; i++) {
    let w = sizes[i].w;
    let h = sizes[i].h;
    let pageId = 3 + i * 3;
    let page = utf8(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + w + ' ' + h + '] ' +
      '/Resources << /XObject << /Im0 ' + (pageId + 1) + ' 0 R >> >> ' +
      '/Contents ' + (pageId + 2) + ' 0 R >>'
    );
    let imgBytes = new Uint8Array(images[i]);
    let img = concat([
      utf8('<< /Type /XObject /Subtype /Image /Width ' + w + ' /Height ' + h +
        ' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ' + imgBytes.length + ' >>' + NEWLINE + 'stream' + NEWLINE),
      imgBytes,
      utf8(NEWLINE + 'endstream')
    ]);
    let contentStr = 'q ' + w + ' 0 0 ' + h + ' 0 0 cm /Im0 Do Q';
    let content = concat([
      utf8('<< /Length ' + contentStr.length + ' >>' + NEWLINE + 'stream' + NEWLINE),
      utf8(contentStr),
      utf8(NEWLINE + 'endstream')
    ]);
    perPage.push([page, img, content]);
  }
  // 组装 PDF：每个对象必须带 "N 0 obj ... endobj" 包裹，xref 偏移指向 obj 标记
  let totalObjects = 2 + perPage.length * 3;
  let offsets: number[] = new Array(totalObjects + 1).fill(0);
  let bodyParts: Uint8Array[] = [utf8('%PDF-1.4' + NEWLINE)];
  let cursor = bodyParts[0].length;
  let pushObj = (num: number, bytes: Uint8Array): void => {
    offsets[num] = cursor;
    let wrapped = concat([
      utf8(String(num) + ' 0 obj' + NEWLINE),
      bytes,
      utf8(NEWLINE + 'endobj' + NEWLINE)
    ]);
    bodyParts.push(wrapped);
    cursor += wrapped.length;
  };
  pushObj(1, catalog);
  pushObj(2, pages);
  let objNum = 3;
  for (let i = 0; i < perPage.length; i++) {
    pushObj(objNum, perPage[i][0]);
    pushObj(objNum + 1, perPage[i][1]);
    pushObj(objNum + 2, perPage[i][2]);
    objNum += 3;
  }
  let body = concat(bodyParts);
  let xrefOffset = body.length;
  let xref = 'xref' + NEWLINE + '0 ' + (totalObjects + 1) + NEWLINE + '0000000000 65535 f ' + NEWLINE;
  for (let i = 1; i <= totalObjects; i++) {
    xref += String(offsets[i]).padStart(10, '0') + ' 00000 n ' + NEWLINE;
  }
  let trailer = utf8(
    xref + 'trailer' + NEWLINE + '<< /Size ' + (totalObjects + 1) + ' /Root 1 0 R >>' + NEWLINE +
    'startxref' + NEWLINE + xrefOffset + NEWLINE + '%%EOF'
  );
  let finalParts = concat([body, trailer]);
  let file = fs.openSync(outPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, finalParts.buffer as ArrayBuffer);
  fs.closeSync(file.fd);
}
