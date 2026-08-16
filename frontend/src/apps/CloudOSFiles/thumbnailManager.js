export const MAX_THUMBNAIL_SOURCE_BYTES = 8 * 1024 * 1024;
export const THUMBNAIL_CONCURRENCY = 3;
export const THUMBNAIL_EDGE_PX = 180;

function abortError() {
  return new DOMException('Miniatura cancelada.', 'AbortError');
}

export class ThumbnailScheduler {
  constructor(limit = THUMBNAIL_CONCURRENCY) {
    this.limit = Math.max(1, Number(limit) || 1);
    this.active = 0;
    this.queue = [];
  }

  schedule(task, signal) {
    if (signal?.aborted) return Promise.reject(abortError());
    return new Promise((resolve, reject) => {
      const job = { task, signal, resolve, reject, started: false, onAbort: null };
      job.onAbort = () => {
        if (job.started) return;
        const index = this.queue.indexOf(job);
        if (index >= 0) this.queue.splice(index, 1);
        reject(abortError());
      };
      signal?.addEventListener('abort', job.onAbort, { once: true });
      this.queue.push(job);
      this.drain();
    });
  }

  drain() {
    while (this.active < this.limit && this.queue.length) {
      const job = this.queue.shift();
      if (job.signal?.aborted) {
        job.signal?.removeEventListener('abort', job.onAbort);
        job.reject(abortError());
        continue;
      }
      job.started = true;
      job.signal?.removeEventListener('abort', job.onAbort);
      this.active += 1;
      Promise.resolve()
        .then(() => job.task(job.signal))
        .then(job.resolve, job.reject)
        .finally(() => {
          this.active -= 1;
          this.drain();
        });
    }
  }
}

export const thumbnailScheduler = new ThumbnailScheduler();

export function thumbnailEligible(file, maxBytes = MAX_THUMBNAIL_SOURCE_BYTES) {
  return Boolean(file && Number.isFinite(file.size) && file.size > 0 && file.size <= maxBytes);
}

export function createBrowserImageThumbnail(file, { signal, maxBytes = MAX_THUMBNAIL_SOURCE_BYTES, edge = THUMBNAIL_EDGE_PX } = {}) {
  if (signal?.aborted) return Promise.reject(abortError());
  // Size is checked before creating an object URL/decoder. Large files remain icon-only.
  if (!thumbnailEligible(file, maxBytes)) return Promise.resolve(null);

  return new Promise((resolve, reject) => {
    const inputUrl = URL.createObjectURL(file);
    const image = new Image();
    let settled = false;
    let outputUrl = null;

    const cleanupInput = () => URL.revokeObjectURL(inputUrl);
    const settle = (callback) => {
      if (settled) return;
      settled = true;
      signal?.removeEventListener('abort', onAbort);
      image.onload = null;
      image.onerror = null;
      cleanupInput();
      callback();
    };
    const onAbort = () => {
      image.src = '';
      if (outputUrl) URL.revokeObjectURL(outputUrl);
      settle(() => reject(abortError()));
    };

    signal?.addEventListener('abort', onAbort, { once: true });
    image.onerror = () => settle(() => resolve(null));
    image.onload = () => {
      if (signal?.aborted) return onAbort();
      const sourceWidth = Math.max(1, image.naturalWidth || image.width || 1);
      const sourceHeight = Math.max(1, image.naturalHeight || image.height || 1);
      const scale = Math.min(1, edge / Math.max(sourceWidth, sourceHeight));
      const width = Math.max(1, Math.round(sourceWidth * scale));
      const height = Math.max(1, Math.round(sourceHeight * scale));
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext('2d', { alpha: true });
      if (!context) return settle(() => resolve(null));
      context.drawImage(image, 0, 0, width, height);
      canvas.toBlob((blob) => {
        if (signal?.aborted) return onAbort();
        if (!blob) return settle(() => resolve(null));
        outputUrl = URL.createObjectURL(blob);
        settle(() => resolve({
          url: outputUrl,
          revoke() {
            if (!outputUrl) return;
            URL.revokeObjectURL(outputUrl);
            outputUrl = null;
          }
        }));
      }, 'image/webp', 0.78);
    };
    image.decoding = 'async';
    image.src = inputUrl;
  });
}

export function scheduleImageThumbnail(fileLoader, options = {}) {
  const signal = options.signal;
  return thumbnailScheduler.schedule(async () => {
    if (signal?.aborted) throw abortError();
    const file = await fileLoader();
    if (signal?.aborted) throw abortError();
    return createBrowserImageThumbnail(file, options);
  }, signal);
}
