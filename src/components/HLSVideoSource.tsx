import React, { useRef, useEffect, useCallback, useState } from 'react';
import type Hls from 'hls.js';

interface HLSVideoSourceProps {
  streamUrl: string;
  onFrame?: (video: HTMLVideoElement) => void;
  onError?: (error: string) => void;
  hidden?: boolean;
  autoPlay?: boolean;
}

export const HLSVideoSource: React.FC<HLSVideoSourceProps> = ({
  streamUrl,
  onFrame,
  onError,
  hidden = true,
  autoPlay = true,
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const frameRef = useRef<number>(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [quality, setQuality] = useState<string>('auto');

  const frameLoop = useCallback(() => {
    const video = videoRef.current;
    if (video && onFrame && video.readyState >= 2) {
      onFrame(video);
    }
    frameRef.current = requestAnimationFrame(frameLoop);
  }, [onFrame]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !streamUrl) return;

    let cancelled = false;

    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }

    const run = async () => {
      if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = streamUrl;
        if (autoPlay) {
          video.play().catch(e => console.log('Autoplay prevented:', e));
        }
        return;
      }

      const HlsModule = (await import(/* webpackChunkName: "hls" */ 'hls.js')).default;
      if (cancelled) return;

      if (!HlsModule.isSupported()) {
        onError?.('HLS not supported in this browser');
        return;
      }

      const hls = new HlsModule({
        maxBufferLength: 30,
        maxMaxBufferLength: 60,
        enableWorker: true,
        lowLatencyMode: true,
        backBufferLength: 90,
      });

      hlsRef.current = hls;

      hls.on(HlsModule.Events.MEDIA_ATTACHED, () => {
        console.log('✅ HLS: Media attached');
      });

      hls.on(HlsModule.Events.MANIFEST_PARSED, (_event, data) => {
        console.log(`✅ HLS: Manifest parsed - ${data.levels.length} quality levels`);
        if (autoPlay) {
          video.play().catch(e => console.log('Autoplay prevented:', e));
        }
      });

      hls.on(HlsModule.Events.ERROR, (_event, data) => {
        if (data.fatal) {
          switch (data.type) {
            case HlsModule.ErrorTypes.NETWORK_ERROR:
              console.log('HLS: Network error, attempting recovery...');
              hls.startLoad();
              break;
            case HlsModule.ErrorTypes.MEDIA_ERROR:
              console.log('HLS: Media error, attempting recovery...');
              hls.recoverMediaError();
              break;
            default:
              onError?.(`HLS fatal error: ${data.type}`);
              hls.destroy();
              break;
          }
        }
      });

      hls.on(HlsModule.Events.LEVEL_SWITCHED, (_event, data) => {
        const level = hls.levels[data.level];
        console.log(`HLS: Quality switched to ${level?.height || 'unknown'}p`);
      });

      hls.loadSource(streamUrl);
      hls.attachMedia(video);
    };

    run();

    frameRef.current = requestAnimationFrame(frameLoop);

    return () => {
      cancelled = true;
      if (frameRef.current) {
        cancelAnimationFrame(frameRef.current);
      }
      hlsRef.current?.destroy();
      hlsRef.current = null;
    };
  }, [streamUrl, autoPlay, frameLoop, onError]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const onPlay = () => setIsPlaying(true);
    const onPause = () => setIsPlaying(false);

    video.addEventListener('play', onPlay);
    video.addEventListener('pause', onPause);

    return () => {
      video.removeEventListener('play', onPlay);
      video.removeEventListener('pause', onPause);
    };
  }, []);

  const setQualityLevel = useCallback((level: number) => {
    const hls = hlsRef.current;
    if (!hls) return;

    if (level === -1) {
      hls.currentLevel = -1;
      setQuality('auto');
    } else {
      hls.currentLevel = level;
      setQuality(`${hls.levels[level]?.height || '?'}p`);
    }
  }, []);

  return (
    <div style={{ display: hidden ? 'none' : 'block' }}>
      <video
        ref={videoRef}
        style={{ width: '100%', height: 'auto' }}
        crossOrigin="anonymous"
        playsInline
        muted
      />
      {!hidden && (
        <div style={{ padding: '8px', background: '#1a1a2e', color: 'white' }}>
          <div>Status: {isPlaying ? '▶️ Playing' : '⏸️ Paused'}</div>
          <div>Quality: {quality}</div>
          {hlsRef.current && (
            <select
              onChange={(e) => setQualityLevel(parseInt(e.target.value))}
              style={{ marginTop: '8px' }}
            >
              <option value="-1">Auto</option>
              {hlsRef.current.levels.map((level, idx) => (
                <option key={idx} value={idx}>
                  {level.height}p ({(level.bitrate / 1000000).toFixed(1)} Mbps)
                </option>
              ))}
            </select>
          )}
        </div>
      )}
    </div>
  );
};

export default HLSVideoSource;
