import React, { useRef, useEffect, useState } from 'react';
import Hls from 'hls.js';

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

    // Clean up previous HLS instance
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }

    setIsReady(false);

    const initHLS = () => {
      if (Hls.isSupported()) {
        const hls = new Hls({
          maxBufferLength: 30,
          maxMaxBufferLength: 60,
          enableWorker: true,
          lowLatencyMode: true,
          backBufferLength: 90,
          // Optimize for real-time shader processing
          maxBufferHole: 0.5,
          highBufferWatchdogPeriod: 1,
        });

        hlsRef.current = hls;

        hls.on(Hls.Events.MEDIA_ATTACHED, () => {
          console.log('🔴 Live Stream: Media attached');
        });

        hls.on(Hls.Events.MANIFEST_PARSED, (_event, data) => {
          console.log(`🔴 Live Stream: Manifest parsed - ${data.levels.length} quality levels`);
          video.play().catch(e => {
            console.log('Autoplay prevented (expected for unmuted):', e);
            // Still mark as ready, user can interact
          });
        });

        hls.on(Hls.Events.LEVEL_SWITCHED, (_event, data) => {
          const level = hls.levels[data.level];
          console.log(`🔴 Live Stream: Quality switched to ${level?.height || 'unknown'}p`);
        });

        hls.on(Hls.Events.ERROR, (_event, data) => {
          console.error('🔴 Live Stream HLS Error:', data);
          if (data.fatal) {
            switch (data.type) {
              case Hls.ErrorTypes.NETWORK_ERROR:
                console.log('🔴 Live Stream: Network error, attempting recovery...');
                hls.startLoad();
                break;
              case Hls.ErrorTypes.MEDIA_ERROR:
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

        // Critical: Wait for video to be ready before notifying
        const handleCanPlay = () => {
          if (!isReady) {
            console.log('🔴 Live Stream: Video ready for WebGPU');
            setIsReady(true);
            onVideoReady(video);
          }
        };

        video.addEventListener('canplay', handleCanPlay);
        video.addEventListener('loadedmetadata', handleCanPlay);

        hls.loadSource(streamUrl);
        hls.attachMedia(video);

        return () => {
          video.removeEventListener('canplay', handleCanPlay);
          video.removeEventListener('loadedmetadata', handleCanPlay);
        };
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        // Native HLS support (Safari) — keep a reference so the listener can be removed
        video.src = streamUrl;
        const handleNativeReady = () => { setIsReady(true); onVideoReady(video); };
        video.addEventListener('loadedmetadata', handleNativeReady);
        return () => video.removeEventListener('loadedmetadata', handleNativeReady);
      } else {
        onError?.('HLS not supported in this browser');
      }
    };

    const cleanup = initHLS();

    return () => {
      cleanup?.();
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
