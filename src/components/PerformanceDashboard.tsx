import React, { useMemo } from 'react';

interface PerformanceDashboardProps {
  fps: number;
  frameTime: number;
  agentCount: number;
  isWASM: boolean;
  streamUrl: string;
}

export const PerformanceDashboard: React.FC<PerformanceDashboardProps> = ({
  fps,
  frameTime,
  agentCount,
  isWASM,
  streamUrl,
}) => {
  // Determine FPS color based on performance
  const fpsColor = useMemo(() => {
    if (fps >= 55) return '#00c853';
    if (fps >= 30) return '#ffc107';
    return '#ff4757';
  }, [fps]);

  // Format frame time
  const formattedFrameTime = useMemo(() => {
    if (frameTime < 1) return `${(frameTime * 1000).toFixed(2)}µs`;
    return `${frameTime.toFixed(2)}ms`;
  }, [frameTime]);

  // Stream status
  const streamStatus = useMemo(() => {
    if (!streamUrl) return { text: 'No Stream', color: '#8b8ba7' };
    if (streamUrl.includes('bilibili')) return { text: 'Bilibili Live', color: '#00a1d6' };
    return { text: 'HLS Stream', color: '#00d4ff' };
  }, [streamUrl]);

  return (
    <div style={styles.container}>
      {/* Left: Renderer Status */}
      <div style={styles.section}>
        <div style={styles.label}>Renderer</div>
        <div style={{
          ...styles.value,
          color: isWASM ? '#00c853' : '#448aff',
        }}>
          {isWASM ? '⚡ C++ WASM' : '🔄 JS WebGPU'}
        </div>
      </div>

      {/* Center: Performance Metrics */}
      <div style={styles.metrics}>
        {/* FPS */}
        <div style={styles.metric}>
          <div style={{ ...styles.metricValue, color: fpsColor }}>
            {fps > 0 ? fps : '--'}
          </div>
          <div style={styles.metricLabel}>FPS</div>
        </div>

        {/* Frame Time */}
        <div style={styles.metric}>
          <div style={styles.metricValue}>
            {fps > 0 ? formattedFrameTime : '--'}
          </div>
          <div style={styles.metricLabel}>Frame Time</div>
        </div>

        {/* Agent Count */}
        <div style={styles.metric}>
          <div style={styles.metricValue}>
            {agentCount >= 1000 
              ? `${(agentCount / 1000).toFixed(1)}K` 
              : agentCount}
          </div>
          <div style={styles.metricLabel}>Agents</div>
        </div>

        {/* Stream Status */}
        <div style={styles.metric}>
          <div style={{ ...styles.metricValue, color: streamStatus.color }}>
            {streamStatus.text}
          </div>
          <div style={styles.metricLabel}>Source</div>
        </div>
      </div>

      {/* Right: Mini Sparkline (placeholder) */}
      <div style={styles.sparklineContainer}>
        <div style={styles.label}>Last 60s</div>
        <FPSGraph fps={fps} />
      </div>
    </div>
  );
};

// Simple FPS graph component
const FPSGraph: React.FC<{ fps: number }> = ({ fps }) => {
  // In a real implementation, this would track FPS history
  const bars = [60, 58, 62, 59, 61, 57, 60, 60, 58, 59];
  
  return (
    <div style={styles.graph}>
      {bars.map((h, i) => (
        <div
          key={i}
          style={{
            ...styles.bar,
            height: `${(h / 70) * 30}px`,
            background: h > 55 ? '#00c853' : h > 30 ? '#ffc107' : '#ff4757',
          }}
        />
      ))}
    </div>
  );
};

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '12px 24px',
    background: '#0f0f1a',
    borderTop: '1px solid #2a2a4a',
    gap: '24px',
  },
  section: {
    minWidth: '120px',
  },
  label: {
    fontSize: '10px',
    color: '#8b8ba7',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
    marginBottom: '4px',
  },
  value: {
    fontSize: '14px',
    fontWeight: 700,
  },
  metrics: {
    display: 'flex',
    gap: '32px',
    flex: 1,
    justifyContent: 'center',
  },
  metric: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
  },
  metricValue: {
    fontSize: '20px',
    fontWeight: 700,
    color: '#fff',
    fontFamily: 'monospace',
  },
  metricLabel: {
    fontSize: '10px',
    color: '#8b8ba7',
    textTransform: 'uppercase',
    marginTop: '2px',
  },
  sparklineContainer: {
    minWidth: '100px',
  },
  graph: {
    display: 'flex',
    alignItems: 'flex-end',
    gap: '2px',
    height: '30px',
  },
  bar: {
    width: '6px',
    borderRadius: '1px',
    transition: 'all 0.3s',
  },
};

export default PerformanceDashboard;
