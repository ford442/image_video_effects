import React, { useState, useCallback } from 'react';

interface BilibiliInputProps {
  onStreamLoaded: (url: string) => void;
}

export const BilibiliInput: React.FC<BilibiliInputProps> = ({ onStreamLoaded }) => {
  const [roomId, setRoomId] = useState('');
  const [customUrl, setCustomUrl] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'bilibili' | 'custom'>('bilibili');

  // Fetch Bilibili stream
  const fetchBilibiliStream = useCallback(async () => {
    if (!roomId.trim()) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      // Try multiple CORS proxies
      const proxies = [
        `https://api.allorigins.win/get?url=${encodeURIComponent(`https://api.live.bilibili.com/room/v1/Room/playUrl?cid=${roomId}&platform=hls&quality=4`)}`,
        `https://corsproxy.io/?${encodeURIComponent(`https://api.live.bilibili.com/room/v1/Room/playUrl?cid=${roomId}&platform=hls&quality=4`)}`,
      ];
      
      let response = null;
      let lastErr = null;
      
      for (const proxy of proxies) {
        try {
          response = await fetch(proxy, { timeout: 10000 } as any);
          if (response.ok) break;
        } catch (e) {
          lastErr = e;
        }
      }
      
      if (!response || !response.ok) {
        throw lastErr || new Error('Failed to fetch');
      }
      
      const data = await response.json();
      const jsonData = data.contents ? JSON.parse(data.contents) : data;
      
      if (jsonData.code !== 0) {
        throw new Error(jsonData.message || 'Room not found or offline');
      }
      
      const urls = jsonData.data?.durl;
      if (!urls || urls.length === 0) {
        throw new Error('No HLS stream available');
      }
      
      const streamUrl = urls[0].url;
      onStreamLoaded(streamUrl);
      
    } catch (err: any) {
      setError(err.message || 'Failed to load stream');
      console.error('Bilibili fetch error:', err);
    } finally {
      setIsLoading(false);
    }
  }, [roomId, onStreamLoaded]);

  // Use custom URL
  const useCustomUrl = useCallback(() => {
    if (!customUrl.trim()) return;
    onStreamLoaded(customUrl);
  }, [customUrl, onStreamLoaded]);

  return (
    <div style={styles.container}>
      {/* Tab Selector */}
      <div style={styles.tabs}>
        <button
          style={{
            ...styles.tab,
            ...(activeTab === 'bilibili' ? styles.tabActive : {}),
          }}
          onClick={() => setActiveTab('bilibili')}
        >
          Bilibili
        </button>
        <button
          style={{
            ...styles.tab,
            ...(activeTab === 'custom' ? styles.tabActive : {}),
          }}
          onClick={() => setActiveTab('custom')}
        >
          Custom URL
        </button>
      </div>

      {/* Bilibili Input */}
      {activeTab === 'bilibili' && (
        <div style={styles.inputGroup}>
          <input
            type="text"
            placeholder="Room ID (e.g., 21495945)"
            value={roomId}
            onChange={(e) => setRoomId(e.target.value)}
            style={styles.input}
            onKeyPress={(e) => e.key === 'Enter' && fetchBilibiliStream()}
          />
          <button
            onClick={fetchBilibiliStream}
            disabled={isLoading || !roomId.trim()}
            style={{
              ...styles.button,
              opacity: isLoading || !roomId.trim() ? 0.5 : 1,
            }}
          >
            {isLoading ? '⏳' : '▶️ Load'}
          </button>
        </div>
      )}

      {/* Custom URL Input */}
      {activeTab === 'custom' && (
        <div style={styles.inputGroup}>
          <input
            type="text"
            placeholder="HLS URL (.m3u8)"
            value={customUrl}
            onChange={(e) => setCustomUrl(e.target.value)}
            style={styles.input}
            onKeyDown={(e) => { if (e.key === 'Enter' && customUrl.trim()) onStreamLoaded(customUrl); }}
          />
          <button
            onClick={useCustomUrl}
            disabled={!customUrl.trim()}
            style={{
              ...styles.button,
              opacity: !customUrl.trim() ? 0.5 : 1,
            }}
          >
            ▶️ Play
          </button>
        </div>
      )}

      {/* Error Display */}
      {error && (
        <div style={styles.error}>
          ⚠️ {error}
        </div>
      )}

      {/* Preset URLs */}
      <div style={styles.presets}>
        <small style={styles.presetLabel}>Test streams:</small>
        <button
          style={styles.presetButton}
          onClick={() => onStreamLoaded('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8')}
        >
          Big Buck Bunny
        </button>
        <button
          style={styles.presetButton}
          onClick={() => onStreamLoaded('https://test-streams.mux.dev/test_001/stream.m3u8')}
        >
          Test Pattern
        </button>
      </div>
    </div>
  );
};

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  tabs: {
    display: 'flex',
    gap: '8px',
  },
  tab: {
    flex: 1,
    padding: '8px 12px',
    background: '#1e1e32',
    border: '1px solid #2a2a4a',
    borderRadius: '6px',
    color: '#8b8ba7',
    cursor: 'pointer',
    fontSize: '12px',
    transition: 'all 0.2s',
  },
  tabActive: {
    background: '#2a2a4a',
    color: '#fff',
    borderColor: '#00d4ff',
  },
  inputGroup: {
    display: 'flex',
    gap: '8px',
  },
  input: {
    flex: 1,
    padding: '10px 12px',
    background: '#1e1e32',
    border: '1px solid #2a2a4a',
    borderRadius: '6px',
    color: '#fff',
    fontSize: '13px',
    outline: 'none',
  },
  button: {
    padding: '10px 16px',
    background: 'linear-gradient(135deg, #00d4ff, #7b2cbf)',
    border: 'none',
    borderRadius: '6px',
    color: '#fff',
    cursor: 'pointer',
    fontSize: '13px',
    fontWeight: 600,
  },
  error: {
    padding: '8px 12px',
    background: 'rgba(255, 71, 87, 0.1)',
    border: '1px solid rgba(255, 71, 87, 0.3)',
    borderRadius: '6px',
    color: '#ff4757',
    fontSize: '12px',
  },
  presets: {
    display: 'flex',
    flexDirection: 'column',
    gap: '6px',
    marginTop: '8px',
  },
  presetLabel: {
    color: '#8b8ba7',
    fontSize: '11px',
  },
  presetButton: {
    padding: '6px 10px',
    background: '#1e1e32',
    border: '1px solid #2a2a4a',
    borderRadius: '4px',
    color: '#8b8ba7',
    cursor: 'pointer',
    fontSize: '11px',
    textAlign: 'left',
  },
};

export default BilibiliInput;
