// ============================================
// ObS Record — Screen Recorder
// ============================================
import { useState, useRef, useEffect, useCallback } from 'react';
import kernel from '../../core/kernel';
import { FiCircle, FiSquare, FiDownload, FiVideo, FiSave,
         FiPause, FiPlay, FiTrash2, FiMic, FiMicOff,
         FiMonitor, FiCamera, FiSettings } from 'react-icons/fi';
import './ObsRecord.css';

// ── Types ─────────────────────────────────────────────────────────────────────

type RecordStatus = 'idle' | 'recording' | 'paused' | 'finished';
type SourceType   = 'screen' | 'camera' | 'both';
type Quality      = 'low' | 'medium' | 'high';

const QUALITY_BITRATE: Record<Quality, number> = {
  low:    500_000,
  medium: 2_500_000,
  high:   8_000_000,
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function formatTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return [h, m, s].map(v => String(v).padStart(2, '0')).join(':');
}

function formatBytes(bytes: number): string {
  if (bytes < 1024)        return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

// ── Component ─────────────────────────────────────────────────────────────────

export default function ObsRecord() {
  // ── State ──────────────────────────────────────────────────────────────────
  const [status,        setStatus]        = useState<RecordStatus>('idle');
  const [sourceType,    setSourceType]    = useState<SourceType>('screen');
  const [quality,       setQuality]       = useState<Quality>('medium');
  const [audioEnabled,  setAudioEnabled]  = useState(true);
  const [fileName,      setFileName]      = useState('');
  const [elapsed,       setElapsed]       = useState(0);
  const [fileSize,      setFileSize]      = useState(0);
  const [videoUrl,      setVideoUrl]      = useState<string | null>(null);
  const [showSettings,  setShowSettings]  = useState(false);
  const [audioLevel,    setAudioLevel]    = useState(0);
  const [error,         setError]         = useState<string | null>(null);

  // ── Refs ───────────────────────────────────────────────────────────────────
  const mediaRecorderRef  = useRef<MediaRecorder | null>(null);
  const streamRef         = useRef<MediaStream | null>(null);
  const chunksRef         = useRef<Blob[]>([]);
  const timerRef          = useRef<ReturnType<typeof setInterval> | null>(null);
  const sizeTimerRef      = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioCtxRef       = useRef<AudioContext | null>(null);
  const analyserRef       = useRef<AnalyserNode | null>(null);
  const audioFrameRef     = useRef<number>(0);
  const liveVideoRef      = useRef<HTMLVideoElement>(null);
  const playbackVideoRef  = useRef<HTMLVideoElement>(null);

  // ── Cleanup on unmount ─────────────────────────────────────────────────────
  useEffect(() => {
    return () => {
      stopTimers();
      streamRef.current?.getTracks().forEach(t => t.stop());
      audioCtxRef.current?.close();
      cancelAnimationFrame(audioFrameRef.current);
      if (videoUrl) URL.revokeObjectURL(videoUrl);
    };
  }, []);

  // ── Live preview ───────────────────────────────────────────────────────────
  useEffect(() => {
    if (status === 'recording' && streamRef.current && liveVideoRef.current) {
      liveVideoRef.current.srcObject = streamRef.current;
    }
  }, [status]);

  // ── Timers ─────────────────────────────────────────────────────────────────
  function startTimers() {
    timerRef.current = setInterval(() => setElapsed(e => e + 1), 1000);
    sizeTimerRef.current = setInterval(() => {
      const bytes = chunksRef.current.reduce((s, c) => s + c.size, 0);
      setFileSize(bytes);
    }, 500);
  }

  function stopTimers() {
    if (timerRef.current)    { clearInterval(timerRef.current);    timerRef.current    = null; }
    if (sizeTimerRef.current){ clearInterval(sizeTimerRef.current); sizeTimerRef.current = null; }
  }

  // ── Audio analyser ─────────────────────────────────────────────────────────
  function startAudioAnalyser(stream: MediaStream) {
    const audioTracks = stream.getAudioTracks();
    if (!audioTracks.length) return;
    try {
      const ctx = new AudioContext();
      const src = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 256;
      src.connect(analyser);
      audioCtxRef.current = ctx;
      analyserRef.current = analyser;

      const data = new Uint8Array(analyser.frequencyBinCount);
      const tick = () => {
        analyser.getByteFrequencyData(data);
        const avg = data.reduce((s, v) => s + v, 0) / data.length;
        setAudioLevel(Math.min(100, (avg / 128) * 100));
        audioFrameRef.current = requestAnimationFrame(tick);
      };
      audioFrameRef.current = requestAnimationFrame(tick);
    } catch { /* AudioContext not available */ }
  }

  function stopAudioAnalyser() {
    cancelAnimationFrame(audioFrameRef.current);
    audioCtxRef.current?.close();
    audioCtxRef.current = null;
    analyserRef.current = null;
    setAudioLevel(0);
  }

  // ── Get stream ─────────────────────────────────────────────────────────────
  async function getStream(): Promise<MediaStream> {
    const videoConstraints = { width: { ideal: 1920 }, height: { ideal: 1080 } };

    if (sourceType === 'camera') {
      return navigator.mediaDevices.getUserMedia({
        video: videoConstraints,
        audio: audioEnabled,
      });
    }

    const screenStream = await navigator.mediaDevices.getDisplayMedia({
      video: { displaySurface: 'browser', ...videoConstraints } as any,
      audio: audioEnabled,
      preferCurrentTab: true,
      selfBrowserSurface: 'include',
    } as any);

    if (sourceType === 'both') {
      try {
        const camStream = await navigator.mediaDevices.getUserMedia({ video: videoConstraints, audio: false });
        const tracks = [...screenStream.getTracks(), ...camStream.getTracks()];
        return new MediaStream(tracks);
      } catch { /* camera unavailable, fall back to screen only */ }
    }

    return screenStream;
  }

  // ── Start recording ────────────────────────────────────────────────────────
  const startRecording = useCallback(async () => {
    setError(null);
    try {
      const stream = await getStream();
      streamRef.current = stream;
      chunksRef.current = [];

      // Pick best supported mimeType
      const mimeType = ['video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm']
        .find(m => MediaRecorder.isTypeSupported(m)) || '';

      const recorder = new MediaRecorder(stream, {
        mimeType: mimeType || undefined,
        videoBitsPerSecond: QUALITY_BITRATE[quality],
      });
      mediaRecorderRef.current = recorder;

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };

      recorder.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: 'video/webm' });
        const url  = URL.createObjectURL(blob);
        setVideoUrl(url);
        setStatus('finished');
        stream.getTracks().forEach(t => t.stop());
        streamRef.current = null;
        stopTimers();
        stopAudioAnalyser();
        kernel.log('INFO', 'ObsRecord', `Gravação finalizada. Tamanho: ${formatBytes(blob.size)}`);
      };

      recorder.start(250); // collect chunks every 250ms
      setStatus('recording');
      setElapsed(0);
      setFileSize(0);
      startTimers();
      if (audioEnabled) startAudioAnalyser(stream);
      kernel.log('INFO', 'ObsRecord', `Gravação iniciada [${quality}, ${sourceType}]`);
    } catch (err: any) {
      const msg = err?.message || 'Permissão negada ou dispositivo indisponível.';
      setError(msg);
      kernel.log('ERROR', 'ObsRecord', `Falha ao iniciar: ${msg}`);
    }
  }, [sourceType, quality, audioEnabled]);

  // ── Stop ───────────────────────────────────────────────────────────────────
  const stopRecording = useCallback(() => {
    mediaRecorderRef.current?.stop();
    setStatus('finished'); // onstop will confirm
  }, []);

  // ── Pause / Resume ─────────────────────────────────────────────────────────
  const togglePause = useCallback(() => {
    const rec = mediaRecorderRef.current;
    if (!rec) return;
    if (status === 'recording') {
      rec.pause();
      stopTimers();
      setStatus('paused');
    } else if (status === 'paused') {
      rec.resume();
      startTimers();
      setStatus('recording');
    }
  }, [status]);

  // ── Discard ────────────────────────────────────────────────────────────────
  const discardRecording = useCallback(() => {
    mediaRecorderRef.current?.stop();
    streamRef.current?.getTracks().forEach(t => t.stop());
    stopTimers();
    stopAudioAnalyser();
    if (videoUrl) { URL.revokeObjectURL(videoUrl); setVideoUrl(null); }
    chunksRef.current = [];
    setStatus('idle');
    setElapsed(0);
    setFileSize(0);
    setFileName('');
  }, [videoUrl]);

  // ── Download to real disk ──────────────────────────────────────────────────
  const downloadFile = useCallback(() => {
    if (!videoUrl) return;
    const a = document.createElement('a');
    a.href = videoUrl;
    a.download = (fileName || `ObsRecord_${Date.now()}`) + '.webm';
    a.click();
    kernel.log('INFO', 'ObsRecord', 'Vídeo baixado para o computador.');
  }, [videoUrl, fileName]);

  // ── Save to VFS ────────────────────────────────────────────────────────────
  const saveToVFS = useCallback(() => {
    if (!chunksRef.current.length) return;
    const blob = new Blob(chunksRef.current, { type: 'video/webm' });
    const reader = new FileReader();
    reader.onloadend = () => {
      try {
        const base64 = reader.result as string;
        const name = (fileName || `Gravação_${Date.now()}`) + '.webm';
        const username = kernel.sysGetSnapshot().user.username;
        let path = `C:\\Users\\${username}\\Videos`;
        if (!kernel.fsGetNode(path)) path = 'C:\\Users\\User\\Videos';
        if (!kernel.fsGetNode(path)) path = 'C:\\Users\\User';
        kernel.fsCreateFile(path, name, base64, 'webm');
        kernel.log('INFO', 'ObsRecord', `Salvo em ${path}\\${name}`);
        alert(`✅ Salvo em: ${path}\\${name}`);
      } catch {
        alert('❌ Erro ao salvar no sistema de arquivos.');
      }
    };
    reader.readAsDataURL(blob);
  }, [fileName]);

  // ── Keyboard shortcut ──────────────────────────────────────────────────────
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'F9') {
        if (status === 'idle')      startRecording();
        else if (status === 'recording' || status === 'paused') stopRecording();
      }
      if (e.key === 'F10' && (status === 'recording' || status === 'paused')) togglePause();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [status, startRecording, stopRecording, togglePause]);

  // ── Render ─────────────────────────────────────────────────────────────────
  const isActive = status === 'recording' || status === 'paused';

  return (
    <div className="obsr-root">

      {/* ── Header ── */}
      <div className="obsr-header">
        <div className="obsr-title">
          <FiVideo className="obsr-title-icon" />
          <span>ObS Record</span>
        </div>

        <div className="obsr-header-right">
          {isActive && (
            <div className="obsr-live-info">
              <span className={`obsr-rec-dot ${status === 'paused' ? 'paused' : ''}`} />
              <span className="obsr-timer">{formatTime(elapsed)}</span>
              <span className="obsr-size">{formatBytes(fileSize)}</span>
            </div>
          )}
          <div className={`obsr-status-badge obsr-status-${status}`}>
            {status === 'idle'      && 'Pronto'}
            {status === 'recording' && 'Gravando'}
            {status === 'paused'    && 'Pausado'}
            {status === 'finished'  && 'Finalizado'}
          </div>
          <button
            className={`obsr-icon-btn ${showSettings ? 'active' : ''}`}
            onClick={() => setShowSettings(s => !s)}
            title="Configurações"
          >
            <FiSettings size={15} />
          </button>
        </div>
      </div>

      {/* ── Settings panel ── */}
      {showSettings && (
        <div className="obsr-settings">
          <div className="obsr-setting-row">
            <span>Fonte</span>
            <div className="obsr-btn-group">
              {(['screen', 'camera', 'both'] as SourceType[]).map(s => (
                <button
                  key={s}
                  className={`obsr-seg-btn ${sourceType === s ? 'active' : ''}`}
                  onClick={() => setSourceType(s)}
                  disabled={isActive}
                >
                  {s === 'screen' && <><FiMonitor size={12} /> Tela</>}
                  {s === 'camera' && <><FiCamera size={12} /> Câmera</>}
                  {s === 'both'   && <><FiMonitor size={12} />+<FiCamera size={12} /> Ambos</>}
                </button>
              ))}
            </div>
          </div>

          <div className="obsr-setting-row">
            <span>Qualidade</span>
            <div className="obsr-btn-group">
              {(['low', 'medium', 'high'] as Quality[]).map(q => (
                <button
                  key={q}
                  className={`obsr-seg-btn ${quality === q ? 'active' : ''}`}
                  onClick={() => setQuality(q)}
                  disabled={isActive}
                >
                  {q === 'low' ? 'Baixa' : q === 'medium' ? 'Média' : 'Alta'}
                </button>
              ))}
            </div>
          </div>

          <div className="obsr-setting-row">
            <span>Áudio</span>
            <button
              className={`obsr-seg-btn ${audioEnabled ? 'active' : ''}`}
              onClick={() => setAudioEnabled(a => !a)}
              disabled={isActive}
            >
              {audioEnabled ? <><FiMic size={12} /> Ativado</> : <><FiMicOff size={12} /> Desativado</>}
            </button>
          </div>
        </div>
      )}

      {/* ── Preview area ── */}
      <div className="obsr-preview">
        {status === 'idle' && !videoUrl && (
          <div className="obsr-placeholder">
            <FiVideo size={52} />
            <p>Pronto para gravar</p>
            <span>F9 para iniciar · F10 para pausar</span>
          </div>
        )}

        {/* Live preview */}
        {isActive && (
          <video
            ref={liveVideoRef}
            className="obsr-video"
            autoPlay
            muted
            playsInline
          />
        )}

        {/* Playback */}
        {status === 'finished' && videoUrl && (
          <video
            ref={playbackVideoRef}
            className="obsr-video"
            src={videoUrl}
            controls
            autoPlay={false}
          />
        )}

        {/* Audio waveform bar */}
        {isActive && audioEnabled && (
          <div className="obsr-audio-bar-wrap">
            <FiMic size={11} />
            <div className="obsr-audio-bar">
              <div
                className="obsr-audio-fill"
                style={{ width: `${audioLevel}%` }}
              />
            </div>
          </div>
        )}
      </div>

      {/* ── Error ── */}
      {error && (
        <div className="obsr-error">
          ⚠ {error}
        </div>
      )}

      {/* ── Controls ── */}
      <div className="obsr-controls">
        {status === 'idle' && (
          <button className="obsr-btn obsr-btn-record" onClick={startRecording}>
            <FiCircle size={14} /> Iniciar Gravação
          </button>
        )}

        {isActive && (
          <>
            <button className="obsr-btn obsr-btn-pause" onClick={togglePause}>
              {status === 'paused' ? <><FiPlay size={14} /> Retomar</> : <><FiPause size={14} /> Pausar</>}
            </button>
            <button className="obsr-btn obsr-btn-stop" onClick={stopRecording}>
              <FiSquare size={14} /> Parar
            </button>
            <button className="obsr-btn obsr-btn-discard" onClick={discardRecording} title="Descartar">
              <FiTrash2 size={14} />
            </button>
          </>
        )}

        {status === 'finished' && (
          <>
            {/* File name input */}
            <input
              className="obsr-filename-input"
              placeholder="Nome do arquivo..."
              value={fileName}
              onChange={e => setFileName(e.target.value)}
              spellCheck={false}
            />
            <button className="obsr-btn obsr-btn-download" onClick={downloadFile} title="Baixar para o computador">
              <FiDownload size={14} /> Baixar
            </button>
            <button className="obsr-btn obsr-btn-save" onClick={saveToVFS} title="Salvar no sistema de arquivos virtual">
              <FiSave size={14} /> Salvar no Sistema
            </button>
            <button className="obsr-btn obsr-btn-discard" onClick={discardRecording} title="Nova gravação">
              <FiTrash2 size={14} /> Nova
            </button>
          </>
        )}
      </div>
    </div>
  );
}
