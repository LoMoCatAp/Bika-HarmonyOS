import { fileIo as fs } from '@kit.CoreFileKit';
import { BikaComicDetail, BikaEpDoc, ComicDetailViewModel, EpViewModel } from '../models/Comic';
import { DownloadTask } from './DownloadManager';

export interface ComicDetailSnapshot {
  version: number;
  comicId: string;
  detail: ComicDetailViewModel | null;
  chapters: EpViewModel[];
  chaptersComplete: boolean;
}

export interface LocalComicDetail {
  comic: ComicDetailViewModel;
  chapters: EpViewModel[];
  detailComplete: boolean;
  chaptersComplete: boolean;
  downloadedOrders: number[];
  localCoverUrl: string;
}

/** 公共作品元数据长期落盘；不保存账号的收藏/点赞状态，不使用有单值大小限制的偏好库。 */
export class ComicDetailStore {
  private static directory: string = '';

  static initialize(filesDir: string): void {
    ComicDetailStore.directory = filesDir + '/bika_metadata';
  }

  private static path(comicId: string): string {
    return ComicDetailStore.directory + '/' + encodeURIComponent(comicId) + '.json';
  }

  private static normalizeChapters(chapters: EpViewModel[]): EpViewModel[] {
    const orders = new Set<number>();
    return chapters.filter((chapter: EpViewModel): boolean => {
      if (!chapter || typeof chapter.id !== 'string' || chapter.id.length === 0
        || !Number.isInteger(chapter.order) || chapter.order <= 0 || orders.has(chapter.order)) {
        return false;
      }
      orders.add(chapter.order);
      return true;
    }).map((chapter: EpViewModel): EpViewModel => {
      const result = new EpViewModel();
      result.id = chapter.id;
      result.order = chapter.order;
      result.title = typeof chapter.title === 'string' && chapter.title.length > 0
        ? chapter.title : '第' + chapter.order + '话';
      return result;
    }).sort((a: EpViewModel, b: EpViewModel): number => a.order - b.order);
  }

  static load(comicId: string): ComicDetailSnapshot | null {
    if (!comicId || !ComicDetailStore.directory) {
      return null;
    }
    try {
      const path = ComicDetailStore.path(comicId);
      if (!fs.accessSync(path)) {
        return null;
      }
      const saved = JSON.parse(fs.readTextSync(path)) as ComicDetailSnapshot;
      if (!saved || saved.version !== 1 || saved.comicId !== comicId || !Array.isArray(saved.chapters)) {
        return null;
      }
      if (saved.detail !== null && (!saved.detail || saved.detail.id !== comicId
        || typeof saved.detail.title !== 'string' || saved.detail.title.length === 0)) {
        return null;
      }
      saved.chapters = ComicDetailStore.normalizeChapters(saved.chapters);
      saved.chaptersComplete = saved.chaptersComplete === true;
      return saved;
    } catch (_err) {
      console.warn('[ComicDetailStore] metadata could not be read');
      return null;
    }
  }

  private static empty(comicId: string): ComicDetailSnapshot {
    return { version: 1, comicId: comicId, detail: null, chapters: [], chaptersComplete: false };
  }

  private static save(snapshot: ComicDetailSnapshot): void {
    if (!ComicDetailStore.directory || !snapshot.comicId) {
      return;
    }
    const path = ComicDetailStore.path(snapshot.comicId);
    const temp = path + '.tmp';
    let file: fs.File | undefined = undefined;
    try {
      if (!fs.accessSync(ComicDetailStore.directory)) {
        fs.mkdirSync(ComicDetailStore.directory, true);
      }
      const content = JSON.stringify(snapshot);
      file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      file = undefined;
      if (fs.readTextSync(temp) !== content) {
        throw new Error('Incomplete metadata write');
      }
      fs.renameSync(temp, path);
    } catch (_err) {
      console.warn('[ComicDetailStore] metadata could not be saved');
    } finally {
      if (file !== undefined) {
        try { fs.closeSync(file); } catch (_err) {}
      }
      try { if (fs.accessSync(temp)) { fs.unlinkSync(temp); } } catch (_err) {}
    }
  }

  static saveDetail(comicId: string, detail: BikaComicDetail): void {
    const snapshot = ComicDetailStore.load(comicId) ?? ComicDetailStore.empty(comicId);
    // 视图模型只包含公共字段，明确排除 isFavourite/isLiked 等账号状态。
    snapshot.detail = ComicDetailViewModel.fromDetail(detail);
    ComicDetailStore.save(snapshot);
  }

  static saveChapters(comicId: string, docs: BikaEpDoc[]): void {
    const snapshot = ComicDetailStore.load(comicId) ?? ComicDetailStore.empty(comicId);
    snapshot.chapters = ComicDetailStore.normalizeChapters(docs.map((doc: BikaEpDoc): EpViewModel => EpViewModel.fromDoc(doc)));
    snapshot.chaptersComplete = snapshot.chapters.length === docs.length;
    ComicDetailStore.save(snapshot);
  }

  private static localCover(tasks: DownloadTask[]): string {
    for (const task of tasks) {
      try {
        if (task.coverLocal && fs.statSync(task.coverLocal).size > 0) {
          return 'file://' + task.coverLocal;
        }
      } catch (_err) {}
    }
    return '';
  }

  /** 兼容旧下载：仅用实际完成的章节恢复可读目录，保留真实话数和稳定的列表键。 */
  static resolve(comicId: string, title: string, tasks: DownloadTask[]): LocalComicDetail | null {
    const saved = ComicDetailStore.load(comicId);
    const matching = tasks.filter((task: DownloadTask): boolean => task.comicId === comicId);
    const completed = matching.filter((task: DownloadTask): boolean => task.status === 'completed'
      && Number.isInteger(task.chapterOrder) && task.chapterOrder > 0 && task.total > 0 && !!task.dir);
    if (saved === null && matching.length === 0) {
      return null;
    }
    const comic = saved?.detail ?? new ComicDetailViewModel();
    if (!saved?.detail) {
      comic.id = comicId;
      comic.title = matching.find((task: DownloadTask): boolean => !!task.comicTitle)?.comicTitle || title || '详情';
      comic.author = matching.find((task: DownloadTask): boolean => !!task.author)?.author || '未知作者';
      comic.description = matching.find((task: DownloadTask): boolean => !!task.description)?.description || '';
      comic.coverUrl = matching.find((task: DownloadTask): boolean => !!task.coverUrl)?.coverUrl || '';
    }
    const chapters = saved?.chapters.slice() ?? [];
    for (const task of completed) {
      if (!chapters.some((chapter: EpViewModel): boolean => chapter.order === task.chapterOrder)) {
        const chapter = new EpViewModel();
        chapter.id = 'download:' + comicId + ':' + task.chapterOrder;
        chapter.order = task.chapterOrder;
        chapter.title = task.chapterTitle || '第' + task.chapterOrder + '话';
        chapters.push(chapter);
      }
    }
    chapters.sort((a: EpViewModel, b: EpViewModel): number => a.order - b.order);
    return { comic: comic, chapters: chapters, detailComplete: saved?.detail !== null && saved?.detail !== undefined,
      chaptersComplete: saved?.chaptersComplete === true, localCoverUrl: ComicDetailStore.localCover(matching),
      downloadedOrders: Array.from(new Set<number>(completed.map((task: DownloadTask): number => task.chapterOrder)))
        .sort((a: number, b: number): number => a - b) };
  }
}
