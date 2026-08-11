import { useState, useRef, useEffect } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { useFileSystem } from '../../stores/fileSystem';
import './MediaPlayer.css';

export default function MediaPlayer({ windowId }: { windowId: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [volume, setVolume] = useState(1);
  const [src, setSrc] = useState<string | null>(null);
  const [mediaTitle, setMediaTitle] = useState('Sem mídia carregada');

  const { getWindow, updateWindowTitle } = useWindowManager();
  const { getNode } = useFileSystem();

  // Load from params if opened from File Explorer
  useEffect(() => {
    const win = getWindow(windowId);
    if (win?.params?.filePath) {
      const path = win.params.filePath;
      const node = getNode(path);
      if (node && node.type === 'file') {
        const title = node.name;
        setMediaTitle(title);
        updateWindowTitle(windowId, `Reproduzindo: ${title}`);

        // Convert the content/object to blob URL if it's not already a URL
        // In local storage webos, we often store recording as blob URLs or base64
        if (node.content?.startsWith('blob:')) {
          setSrc(node.content);
        } else if (node.content?.startsWith('data:video')) {
          setSrc(node.content);
        } else {
            // MOCK: In a real system we would read the disk
           console.log("Mídia não suportada ou formato incompatível", node.content);
        }
      }
    }
  }, [windowId, getWindow, getNode, updateWindowTitle]);

  const togglePlay = () => {
    if (!videoRef.current) return;
    if (isPlaying) {
      videoRef.current.pause();
    } else {
      videoRef.current.play();
    }
    setIsPlaying(!isPlaying);
  };

  const handleTimeUpdate = () => {
    if (!videoRef.current) return;
    const current = videoRef.current.currentTime;
    const total = videoRef.current.duration;
    setCurrentTime(current);
    setProgress((current / total) * 100);
  };

  const handleLoadedMetadata = () => {
    if (!videoRef.current) return;
    setDuration(videoRef.current.duration);
  };

  const handleSeek = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!videoRef.current || !duration) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const percent = x / rect.width;
    const newTime = percent * duration;
    videoRef.current.currentTime = newTime;
    setProgress(percent * 100);
  };

  const formatTime = (seconds: number) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    return `${h > 0 ? h + ':' : ''}${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  };

  return (
    <div className="media-player">
      <div className="player-container">
        {src ? (
          <>
            <video
              ref={videoRef}
              className="player-video"
              src={src}
              onTimeUpdate={handleTimeUpdate}
              onLoadedMetadata={handleLoadedMetadata}
              onEnded={() => setIsPlaying(false)}
              onClick={togglePlay}
            />

            <div className="player-controls">
              <div className="player-progress-container" onClick={handleSeek}>
                <div className="player-progress-bar" style={{ width: `${progress}%` }}>
                  <div className="player-progress-knob" />
                </div>
              </div>

              <div className="player-actions">
                <button className="player-btn" onClick={togglePlay}>
                  {isPlaying ? (
                    <svg viewBox="0 0 24 24" fill="currentColor">
                      <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/>
                    </svg>
                  ) : (
                    <svg viewBox="0 0 24 24" fill="currentColor">
                      <path d="M8 5v14l11-7z"/>
                    </svg>
                  )}
                </button>

                <div className="player-volume-container">
                    <svg viewBox="0 0 24 24" fill="currentColor" width="20">
                      <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/>
                    </svg>
                    <input 
                      type="range" 
                      className="player-volume-slider" 
                      min="0" max="1" step="0.1" 
                      value={volume}
                      onChange={(e) => {
                        const v = parseFloat(e.target.value);
                        setVolume(v);
                        if(videoRef.current) videoRef.current.volume = v;
                      }}
                    />
                </div>

                <div className="player-time">
                  {formatTime(currentTime)} / {formatTime(duration)}
                </div>

                <button className="player-btn" onClick={() => videoRef.current?.requestFullscreen()}>
                   <svg viewBox="0 0 24 24" fill="currentColor">
                     <path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/>
                   </svg>
                </button>
              </div>
            </div>
          </>
        ) : (
          <div className="player-empty">
            <div className="player-drop-zone">
               <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1" width="64">
                 <path d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
               </svg>
               <h3>{mediaTitle === 'Sem mídia carregada' ? 'Abra um vídeo para começar' : mediaTitle}</h3>
               <p>Selecione uma gravação no Gerenciador de Arquivos</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
