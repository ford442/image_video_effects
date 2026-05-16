/**
 * LiveStreamPanel.tsx
 *
 * Component for managing live stream input from Bilibili or direct HLS URLs.
 */

import React, { useState } from 'react';

export interface LiveStreamPanelProps {
  liveStreamUrl?: string;
  onLiveStreamLoaded?: (url: string) => void;
  onExitLiveStream?: () => void;
}

/**
 * Fetches M3U8 URL from Bilibili live stream
 */
async function getBilibiliLiveM3U8(roomId: string): Promise<string> {
  try {
    const res = await fetch(
      `https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=${roomId}&protocol=0,1&format=0,1,2&codec=0,1&qn=10000&platform=web`
    );
    const data = await res.json();
    if (data.code !== 0 || !data.data?.play_url_list?.[0]) {
      throw new Error('Failed to get stream URL');
    }
    const urls = data.data.play_url_list[0]?.play_url || [];
    if (urls.length === 0) throw new Error('No URLs available');
    return urls[0];
  } catch (error: any) {
    throw new Error(`Bilibili API error: ${error.message}`);
  }
}

export const LiveStreamPanel: React.FC<LiveStreamPanelProps> = ({
  liveStreamUrl,
  onLiveStreamLoaded,
  onExitLiveStream,
}) => {
  const [liveInput, setLiveInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleStartStream = async () => {
    if (!liveInput.trim()) return;

    setIsLoading(true);
    setError(null);

    try {
      let url = liveInput.trim();

      // If it's just numbers, treat as Bilibili room ID
      if (/^\d+$/.test(url)) {
        url = await getBilibiliLiveM3U8(url);
      }

      onLiveStreamLoaded?.(url);
    } catch (err: any) {
      setError(err.message || 'Failed to load stream');
    } finally {
      setIsLoading(false);
    }
  };

  if (liveStreamUrl) {
    return (
      <div
        className="glass-panel"
        style={{
          marginTop: '10px',
          padding: '16px',
          borderColor: 'rgba(46, 213, 115, 0.3)',
        }}
      >
        <h3
          style={{
            color: '#2ed573',
            fontWeight: 'bold',
            marginBottom: '12px',
            fontSize: '14px',
          }}
        >
          🎥 Live Stream Active
        </h3>

        <div
          className="glass-card"
          style={{
            marginBottom: '12px',
            fontSize: '12px',
          }}
        >
          <span style={{ color: '#2ed573' }}>● Connected</span>
          <span style={{ color: '#a0a0b0', marginLeft: '8px', wordBreak: 'break-all' }}>
            {liveStreamUrl.length > 35 ? liveStreamUrl.substring(0, 35) + '...' : liveStreamUrl}
          </span>
        </div>

        <button
          onClick={() => {
            onExitLiveStream?.();
            setLiveInput('');
          }}
          className="record-btn-gold"
        >
          ⏹ Disconnect
        </button>
      </div>
    );
  }

  return (
    <div
      className="glass-panel"
      style={{
        marginTop: '10px',
        padding: '16px',
      }}
    >
      <h3
        style={{
          color: '#e94560',
          fontWeight: 'bold',
          marginBottom: '12px',
          fontSize: '14px',
        }}
      >
        🎥 Live Bilibili Stream
      </h3>

      <input
        type="text"
        className="glass-input"
        placeholder="Bilibili Room ID or direct .m3u8 URL"
        value={liveInput}
        onChange={(e) => setLiveInput(e.target.value)}
        onKeyPress={(e) => e.key === 'Enter' && handleStartStream()}
        style={{
          marginBottom: '12px',
        }}
      />

      {error && (
        <div
          className="glass-card"
          style={{
            borderColor: 'rgba(255, 71, 87, 0.3)',
            background: 'rgba(255, 71, 87, 0.1)',
            color: '#ff6b6b',
            fontSize: '12px',
            marginBottom: '12px',
          }}
        >
          ⚠️ {error}
        </div>
      )}

      <button
        onClick={handleStartStream}
        disabled={isLoading || !liveInput.trim()}
        className="record-btn-gold"
        style={{
          opacity: isLoading || !liveInput.trim() ? 0.7 : 1,
        }}
      >
        {isLoading ? '⏳ Loading...' : '▶️ Start Live Stream'}
      </button>

      <div
        className="glass-card"
        style={{
          marginTop: '12px',
          fontSize: '11px',
          color: '#a0a0b0',
        }}
      >
        <strong style={{ color: '#FFD700' }}>Tip:</strong> Try room IDs like{' '}
        <code
          style={{
            background: 'rgba(255,215,0,0.1)',
            color: '#FFD700',
            padding: '2px 6px',
            borderRadius: '4px',
          }}
        >
          21495945
        </code>{' '}
        or paste a direct HLS URL
      </div>
    </div>
  );
};
