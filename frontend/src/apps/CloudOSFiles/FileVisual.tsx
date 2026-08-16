import { useEffect, useMemo, useState } from 'react';
import type { IconType } from 'react-icons';
import { FaFile, FaFileAlt, FaFileArchive, FaFileAudio, FaFileCode, FaFileImage, FaFilePdf, FaFileVideo, FaFolder, FaLink, FaMarkdown, FaMicrochip } from 'react-icons/fa';
import { VscJson } from 'react-icons/vsc';
import { canGenerateImageThumbnail, classifyFileVisual, fileVisualLabel, type FileVisualKind } from './fileVisualPolicy.js';
import { scheduleImageThumbnail, type ThumbnailResult } from './thumbnailManager.js';
import { fileSourceFacade, type CloudFileEntry } from './fileSourceFacade';
import type { FileSourceKind } from './fileSourcePolicy';
import './CloudOSFiles.visual.css';

const ICONS: Record<FileVisualKind, IconType> = {
  folder: FaFolder,
  text: FaFileAlt,
  markdown: FaMarkdown,
  code: FaFileCode,
  json: VscJson,
  pdf: FaFilePdf,
  image: FaFileImage,
  audio: FaFileAudio,
  video: FaFileVideo,
  archive: FaFileArchive,
  executable: FaMicrochip,
  symlink: FaLink,
  unknown: FaFile,
};

const MAX_THUMBNAIL_READ_BYTES = 8 * 1024 * 1024;

export default function FileVisual({
  entry,
  source,
  path,
  fromTrash = false,
  compact = false,
}: {
  entry: CloudFileEntry;
  source: FileSourceKind;
  path: string[];
  fromTrash?: boolean;
  compact?: boolean;
}) {
  const kind = useMemo(() => classifyFileVisual(entry), [entry]);
  const [thumbnail, setThumbnail] = useState<ThumbnailResult>(null);
  const Icon = ICONS[kind];
  const pathKey = path.join('\u0000');

  useEffect(() => {
    const controller = new AbortController();
    let owned: ThumbnailResult = null;
    setThumbnail(null);

    const thumbnailAllowed = !fromTrash && entry.kind === 'file' && !entry.symlink && canGenerateImageThumbnail(entry) && entry.size > 0 && entry.size <= MAX_THUMBNAIL_READ_BYTES;
    if (!thumbnailAllowed) return () => controller.abort();

    void scheduleImageThumbnail(
      () => fileSourceFacade.readFile(source, path, entry, MAX_THUMBNAIL_READ_BYTES),
      { signal: controller.signal, maxBytes: MAX_THUMBNAIL_READ_BYTES },
    ).then((result) => {
      if (controller.signal.aborted) {
        result?.revoke();
        return;
      }
      owned = result;
      setThumbnail(result);
    }).catch((error) => {
      if (error?.name !== 'AbortError') setThumbnail(null);
    });

    return () => {
      controller.abort();
      owned?.revoke();
    };
  }, [entry.kind, entry.name, entry.originalName, entry.size, entry.symlink, fromTrash, pathKey, source]);

  return (
    <div className={`cf-visual cf-visual-${kind}${compact ? ' compact' : ''}`} data-file-visual={kind} title={fileVisualLabel(kind)}>
      {thumbnail ? <img className="cf-thumbnail" src={thumbnail.url} alt="" draggable={false} /> : <Icon aria-hidden={true} />}
    </div>
  );
}
