export const MAX_THUMBNAIL_SOURCE_BYTES: number;
export const THUMBNAIL_CONCURRENCY: number;
export const THUMBNAIL_EDGE_PX: number;
export type ThumbnailResult = { url: string; revoke: () => void } | null;
export class ThumbnailScheduler {
  constructor(limit?: number);
  limit: number;
  active: number;
  queue: unknown[];
  schedule<T>(task: (signal?: AbortSignal) => Promise<T> | T, signal?: AbortSignal): Promise<T>;
  drain(): void;
}
export const thumbnailScheduler: ThumbnailScheduler;
export function thumbnailEligible(file: Pick<File, 'size'> | null | undefined, maxBytes?: number): boolean;
export function createBrowserImageThumbnail(file: File, options?: { signal?: AbortSignal; maxBytes?: number; edge?: number }): Promise<ThumbnailResult>;
export function scheduleImageThumbnail(fileLoader: () => Promise<File>, options?: { signal?: AbortSignal; maxBytes?: number; edge?: number }): Promise<ThumbnailResult>;
