import React, { useRef, useEffect, useCallback, useState } from 'react';
import Hls from 'hls.js';

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
  const frameRef = useRef<number>();
  const [isPlaying, setIsPlaying] = useState(false);
  const [quality, setQuality] = useState<string>('auto');

  // Frame callback for WASM
  const frameLoop = useCallback(() => {
    const video = videoRef.current;
    if (video && onFrame && video.readyState >= 2) {
      onFrame(video);
    }
    frameRef.current = requestAnimationFrame(frameLoop);
  }, [onFrame]);

  // Initialize HLS
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !streamUrl) return;

    if (Hls.isSupported()) {
      const hls = new Hls({
        maxBufferLength: 30,
        maxMaxBufferLength: 60,
        enableWorker: true,
        lowLatencyMode: true,
        backBufferLength: 90,
      });

      hlsRef.current = hls;

      hls.on(Hls.Events.MEDIA_ATTACHED, () => {
        console.log('✅ HLS: Media attached');
      });

      hls.on(Hls.Events.MANIFEST_PARSED, (event, data) => {
        console.log(`✅ HLS: Manifest parsed - ${data.levels.length} quality levels`);
        if (autoPlay) {
          video.play().catch(e => console.log('Autoplay prevented:', e));
        }
      });

      hls.on(Hls.Events.ERROR, (event, data) => {
        if (data.fatal) {
          switch (data.type) {
            case Hls.ErrorTypes.NETWORK_ERROR:
              console.log('HLS: Network error, attempting recovery...');
              hls.startLoad();
              break;
            case Hls.ErrorTypes.MEDIA_ERROR:
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

      hls.on(Hls.Events.LEVEL_SWITCHED, (event, data) => {
        const level = hls.levels[data.level];
        console.log(`HLS: Quality switched to ${level?.height || 'unknown'}p`);
      });

      hls.loadSource(streamUrl);
      hls.attachMedia(video);
    } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
      // Native HLS support (Safari)
      video.src = streamUrl;
      if (autoPlay) {
        video.play().catch(e => console.log('Autoplay prevented:', e));
      }
    } else {
      onError?.('HLS not supported in this browser');
    }

    // Start frame loop
    frameRef.current = requestAnimationFrame(frameLoop);

    return () => {
      if (frameRef.current) {
        cancelAnimationFrame(frameRef.current);
      }
      hlsRef.current?.destroy();
    };
  }, [streamUrl, autoPlay, frameLoop, onError]);

  // Video event handlers
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

  // Quality selector helper
  const setQualityLevel = useCallback((level: number) => {
    const hls = hlsRef.current;
    if (!hls) return;

    if (level === -1) {
      hls.currentLevel = -1; // Auto
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
