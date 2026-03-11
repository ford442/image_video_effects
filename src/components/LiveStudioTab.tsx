import React, { useState, useRef, useCallback, useEffect } from 'react';
import { HLSVideoSource } from './HLSVideoSource';
import { RendererToggle } from './RendererToggle';
import { PerformanceDashboard } from './PerformanceDashboard';
import { PhysarumControls } from './PhysarumControls';
import { DanmakuOverlay } from './DanmakuOverlay';
import { BilibiliInput } from './BilibiliInput';
import { usePerformanceMonitor } from '../hooks/usePerformanceMonitor';
import { useAudioAnalyzer } from '../hooks/useAudioAnalyzer';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { JSRenderer } from '../renderer/JSRenderer';
import { type Renderer, DEFAULT_CONFIG } from '../renderer/Renderer';

interface LiveStudioTabProps {
  className?: string;
}

export const LiveStudioTab: React.FC<LiveStudioTabProps> = ({ className }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const rendererRef = useRef<Renderer | null>(null);
  const [useWasm, setUseWasm] = useState(false);
  const [streamUrl, setStreamUrl] = useState<string>('');
  const [isLoading, setIsLoading] = useState(false);
  const [agentCount, setAgentCount] = useState(DEFAULT_CONFIG.agentCount);

  const { fps, frameTime, startMonitoring, stopMonitoring } = usePerformanceMonitor();
  const { startAudio, stopAudio, getAudioData } = useAudioAnalyzer();

  // Initialize renderer
  const initRenderer = useCallback(async (wasmMode: boolean) => {
    if (!canvasRef.current) return;

    setIsLoading(true);

    // Destroy old renderer
    rendererRef.current?.destroy();

    // Create new renderer
    const RendererClass = wasmMode ? WASMRenderer : JSRenderer;
    const renderer = new RendererClass({
      ...DEFAULT_CONFIG,
      agentCount,
    }) as Renderer;

    const success = await renderer.init(canvasRef.current);

    if (success) {
      rendererRef.current = renderer;
      setUseWasm(wasmMode);
      startMonitoring();
      startAudio();

      // Connect video if available
      if (videoRef.current) {
        renderer.setVideo(videoRef.current);
      }
    }

    setIsLoading(false);
  }, [agentCount, startMonitoring, startAudio]);

  // Handle video frame updates
  const handleVideoFrame = useCallback((video: HTMLVideoElement) => {
    videoRef.current = video;
    rendererRef.current?.setVideo(video);
    rendererRef.current?.updateVideoFrame();
  }, []);

  // Handle audio updates
  useEffect(() => {
    if (!rendererRef.current) return;

    const interval = setInterval(() => {
      const audio = getAudioData();
      rendererRef.current?.updateAudioData(audio.bass, audio.mid, audio.treble);
    }, 50);

    return () => clearInterval(interval);
  }, [getAudioData]);

  // Handle mouse movement
  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    if (!canvasRef.current || !rendererRef.current) return;

    const rect = canvasRef.current.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width;
    const y = (e.clientY - rect.top) / rect.height;

    rendererRef.current.updateMouse(x, y);
  }, []);

  // Handle parameter changes
  const handleParamChange = useCallback((name: string, value: number) => {
    rendererRef.current?.setParam(name, value);

    if (name === 'agentCount') {
      setAgentCount(Math.floor(value));
    }
  }, []);

  // Handle Bilibili stream
  const handleBilibiliStream = useCallback((url: string) => {
    setStreamUrl(url);
  }, []);

  // Cleanup
  useEffect(() => {
    return () => {
      rendererRef.current?.destroy();
      stopMonitoring();
      stopAudio();
    };
  }, [stopMonitoring, stopAudio]);

  // Initialize JS renderer by default
  useEffect(() => {
    initRenderer(false);
  }, []);

  return (
    <div className={`live-studio-tab ${className || ''}`} style={styles.container}>
      {/* Header */}
      <div style={styles.header}>
        <h2 style={styles.title}>🎥 LIVE STUDIO</h2>
        <RendererToggle
          isWASM={useWasm}
          onToggle={initRenderer}
          isLoading={isLoading}
        />
      </div>

      {/* Main Content */}
      <div style={styles.mainContent}>
        {/* Video Canvas Area */}
        <div style={styles.videoArea}>
          <canvas
            ref={canvasRef}
            width={DEFAULT_CONFIG.width}
            height={DEFAULT_CONFIG.height}
            style={styles.canvas}
            onMouseMove={handleMouseMove}
          />

          {/* Hidden HLS Video */}
          {streamUrl && (
            <HLSVideoSource
              streamUrl={streamUrl}
              onFrame={handleVideoFrame}
              hidden={true}
            />
          )}

          {/* Danmaku Overlay */}
          <DanmakuOverlay
            enabled={true}
            opacity={0.7}
          />
        </div>

        {/* Sidebar Controls */}
        <div style={styles.sidebar}>
          {/* Stream Selector */}
          <div style={styles.section}>
            <h3 style={styles.sectionTitle}>Stream Source</h3>
            <BilibiliInput onStreamLoaded={handleBilibiliStream} />
          </div>

          {/* Physarum Controls */}
          <div style={styles.section}>
            <h3 style={styles.sectionTitle}>Swarm Controls</h3>
            <PhysarumControls onParamChange={handleParamChange} />
          </div>
        </div>
      </div>

      {/* Status Bar */}
      <PerformanceDashboard
        fps={fps}
        frameTime={frameTime}
        agentCount={agentCount}
        isWASM={useWasm}
        streamUrl={streamUrl}
      />
    </div>
  );
};

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    height: '100vh',
    background: '#0a0a0f',
    color: '#fff',
    fontFamily: 'system-ui, -apple-system, sans-serif',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '12px 24px',
    background: '#16162a',
    borderBottom: '1px solid #2a2a4a',
  },
  title: {
    margin: 0,
    fontSize: '20px',
    fontWeight: 600,
    background: 'linear-gradient(90deg, #00d4ff, #7b2cbf)',
    WebkitBackgroundClip: 'text',
    WebkitTextFillColor: 'transparent',
  },
  mainContent: {
    display: 'flex',
    flex: 1,
    overflow: 'hidden',
  },
  videoArea: {
    flex: 1,
    position: 'relative',
    background: '#000',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  canvas: {
    maxWidth: '100%',
    maxHeight: '100%',
    objectFit: 'contain',
  },
  sidebar: {
    width: '300px',
    background: '#12121f',
    borderLeft: '1px solid #2a2a4a',
    padding: '16px',
    overflowY: 'auto',
  },
  section: {
    marginBottom: '24px',
  },
  sectionTitle: {
    margin: '0 0 12px 0',
    fontSize: '14px',
    fontWeight: 600,
    color: '#8b8ba7',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
};

export default LiveStudioTab;
