

export interface WidgetActionParams {
  action?: string;
  comicId?: string;
  comicTitle?: string;
  timestamp?: number;
  /** 应用接续专用：源端话数 / 页码 / 封面（仅 continuation_reading 时有值） */
  order?: number;
  page?: number;
  coverUrl?: string;
  /** 通用页面接续（action = continuation_navigate）：目标 route 与参数 JSON */
  route?: string;
  paramsJson?: string;
}

export interface SubpageOpenSignal {
  name: string;
  timestamp: number;
}
