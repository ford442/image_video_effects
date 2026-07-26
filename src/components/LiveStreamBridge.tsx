import React, { useRef, useEffect, useState } from 'react';
import type Hls from 'hls.js';

interface LiveStreamBridgeProps {
  streamUrl: string;
  onVideoReady: (video: HTMLVideoElement) => void;
  onError?: (error: string) => void;
}

export const LiveStreamBridge: React.FC<LiveStreamBridgeProps> = ({
  streamUrl,
  onVideoReady,
  onError
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !streamUrl) return;

    let cancelled = false;
    let listenerCleanup: (() => void) | undefined;

    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }

    setIsReady(false);

    const run = async () => {
      if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = streamUrl;
        const handleNativeReady = () => {
          if (!cancelled) {
            setIsReady(true);
            onVideoReady(video);
          }
        };
        video.addEventListener('loadedmetadata', handleNativeReady);
        listenerCleanup = () => video.removeEventListener('loadedmetadata', handleNativeReady);
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
        maxBufferHole: 0.5,
        highBufferWatchdogPeriod: 1,
      });

      hlsRef.current = hls;

      hls.on(HlsModule.Events.MEDIA_ATTACHED, () => {
        console.log('🔴 Live Stream: Media attached');
      });

      hls.on(HlsModule.Events.MANIFEST_PARSED, (_event, data) => {
        console.log(`🔴 Live Stream: Manifest parsed - ${data.levels.length} quality levels`);
        video.play().catch(e => {
          console.log('Autoplay prevented (expected for unmuted):', e);
        });
      });

      hls.on(HlsModule.Events.LEVEL_SWITCHED, (_event, data) => {
        const level = hls.levels[data.level];
        console.log(`🔴 Live Stream: Quality switched to ${level?.height || 'unknown'}p`);
      });

      hls.on(HlsModule.Events.ERROR, (_event, data) => {
        console.error('🔴 Live Stream HLS Error:', data);
        if (data.fatal) {
          switch (data.type) {
            case HlsModule.ErrorTypes.NETWORK_ERROR:
              console.log('🔴 Live Stream: Network error, attempting recovery...');
              hls.startLoad();
              break;
            case HlsModule.ErrorTypes.MEDIA_ERROR:
              console.log('🔴 Live Stream: Media error, attempting recovery...');
              hls.recoverMediaError();
              break;
            default:
              onError?.(`Fatal error: ${data.type}`);
              hls.destroy();
              break;
          }
        }
      });

      const handleCanPlay = () => {
        if (!isReady && !cancelled) {
          console.log('🔴 Live Stream: Video ready for WebGPU');
          setIsReady(true);
          onVideoReady(video);
        }
      };

      video.addEventListener('canplay', handleCanPlay);
      video.addEventListener('loadedmetadata', handleCanPlay);

      hls.loadSource(streamUrl);
      hls.attachMedia(video);

      listenerCleanup = () => {
        video.removeEventListener('canplay', handleCanPlay);
        video.removeEventListener('loadedmetadata', handleCanPlay);
      };
    };

    run();

    return () => {
      cancelled = true;
      listenerCleanup?.();
      hlsRef.current?.destroy();
      hlsRef.current = null;
    };
  }, [streamUrl, onVideoReady, onError, isReady]);

  return (
    <video
      ref={videoRef}
      crossOrigin="anonymous"
      playsInline
      muted
      preload="auto"
      style={{
        position: 'absolute',
        opacity: 0,
        pointerEvents: 'none',
        width: '1px',
        height: '1px',
        zIndex: -1
      }}
    />
  );
};

export default LiveStreamBridge;
