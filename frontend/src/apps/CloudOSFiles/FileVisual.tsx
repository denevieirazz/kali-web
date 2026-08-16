import { useEffect, useMemo, useState, type ComponentType } from 'react';
import { FaFile, FaFileAlt, FaFileArchive, FaFileAudio, FaFileCode, FaFileImage, FaFilePdf, FaFileVideo, FaFolder, FaLink, FaMarkdown, FaMicrochip } from 'react-icons/fa';
import { VscJson } from 'react-icons/vsc';
import { canGenerateImageThumbnail, classifyFileVisual, fileVisualLabel, type FileVisualKind } from './fileVisualPolicy.js';
import { scheduleImageThumbnail, type ThumbnailResult } from './thumbnailManager.js';
import { readFile, type FileEntry } from './opfsFileService';
import './CloudOSFiles.visual.css';

const ICONS: Record<FileVisualKind, ComponentType<{ 'aria-hidden'?: boolean }>> = {
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

export default function FileVisual({ entry, path, fromTrash = false, compact = false }: { entry: FileEntry; path: string[]; fromTrash?: boolean; compact?: boolean }) {
  const kind = useMemo(() => classifyFileVisual(entry), [entry]);
  const [thumbnail, setThumbnail] = useState<ThumbnailResult>(null);
  const Icon = ICONS[kind];
  const pathKey = path.join('\u0000');

  useEffect(() => {
    const controller = new AbortController();
    let owned: ThumbnailResult = null;
    setThumbnail(null);
    if (!canGenerateImageThumbnail(entry)) return () => controller.abort();

    void scheduleImageThumbnail(() => readFile(path, entry.name, fromTrash), { signal: controller.signal }).then((result) => {
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
  // pathKey is the stable identity of the OPFS location; path itself may be a new array after navigation.
  }, [entry.kind, entry.name, entry.originalName, fromTrash, pathKey]);

  return (
    <div className={`cf-visual cf-visual-${kind}${compact ? ' compact' : ''}`} data-file-visual={kind} title={fileVisualLabel(kind)}>
      {thumbnail ? <img className="cf-thumbnail" src={thumbnail.url} alt="" draggable={false} /> : <Icon aria-hidden={true} />}
    </div>
  );
}
