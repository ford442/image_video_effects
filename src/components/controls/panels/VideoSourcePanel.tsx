import React from 'react';
import { InputSource } from '../../../renderer/types';
import { VideoRecord } from '../../../syncTypes';

export interface VideoSourcePanelProps {
    selectedVideo: string;
    setSelectedVideo: (video: string) => void;
    setInputSource: (source: InputSource) => void;
    videoList: VideoRecord[];
    videoB3hdMode?: boolean;
    setVideoB3hdMode?: (enabled: boolean) => void;
    b3hdSegmentLength?: number;
    setB3hdSegmentLength?: (len: number) => void;
    b3hdIntervalSeconds?: number;
    setB3hdIntervalSeconds?: (sec: number) => void;
    currentSegment?: { video: VideoRecord; start: number; end: number } | null;
    onUploadVideoTrigger: () => void;
    isMuted: boolean;
    setIsMuted: (muted: boolean) => void;
}

export const VideoSourcePanel: React.FC<VideoSourcePanelProps> = ({
    selectedVideo,
    setSelectedVideo,
    setInputSource,
    videoList,
    videoB3hdMode,
    setVideoB3hdMode,
    b3hdSegmentLength,
    setB3hdSegmentLength,
    b3hdIntervalSeconds,
    setB3hdIntervalSeconds,
    currentSegment,
    onUploadVideoTrigger,
    isMuted,
    setIsMuted,
}) => (
    <div className="control-group glass-panel" style={{ marginTop: '10px', padding: '12px' }}>
        <div className="gold-section-header" style={{ fontSize: '12px', marginTop: '0' }}>Select Video</div>
        <select
            value={selectedVideo}
            onChange={(e) => {
                setSelectedVideo(e.target.value);
                setInputSource('video');
                if (setVideoB3hdMode) setVideoB3hdMode(false);
            }}
            className="glass-select"
            style={{ marginBottom: '10px' }}
        >
            <option value="" disabled>Select a Video...</option>
            {videoList.map((v) => {
                const fileName = v.title || v.url.split('/').pop() || v.url;
                const durationLabel = typeof v.duration === 'number' ? ` (${Math.round(v.duration)}s)` : '';
                return (
                    <option key={v.url} value={v.url}>
                        {fileName}{durationLabel}
                    </option>
                );
            })}
        </select>

        {setVideoB3hdMode && (
            <label style={{ display: 'flex', alignItems: 'center', color: '#a0a0b0', fontSize: '13px', marginBottom: '10px' }}>
                <input
                    type="checkbox"
                    className="gold-checkbox"
                    checked={!!videoB3hdMode}
                    onChange={(e) => setVideoB3hdMode(e.target.checked)}
                    style={{ marginRight: '8px' }}
                /> B3HD Rotation Mode
            </label>
        )}

        {videoB3hdMode && setB3hdSegmentLength && setB3hdIntervalSeconds && (
            <>
                <div style={{ marginBottom: '10px' }}>
                    <label style={{ display: 'block', color: '#a0a0b0', fontSize: '12px', marginBottom: '4px' }}>
                        Clip Duration: {b3hdSegmentLength}s
                    </label>
                    <input
                        type="range"
                        className="glass-range"
                        min="1"
                        max="60"
                        step="1"
                        value={b3hdSegmentLength}
                        onChange={(e) => setB3hdSegmentLength(Number(e.target.value))}
                        style={{ width: '100%' }}
                    />
                </div>
                <div style={{ marginBottom: '10px' }}>
                    <label style={{ display: 'block', color: '#a0a0b0', fontSize: '12px', marginBottom: '4px' }}>
                        Time Between Clips: {b3hdIntervalSeconds}s
                    </label>
                    <input
                        type="range"
                        className="glass-range"
                        min="0"
                        max="10"
                        step="0.5"
                        value={b3hdIntervalSeconds}
                        onChange={(e) => setB3hdIntervalSeconds(Number(e.target.value))}
                        style={{ width: '100%' }}
                    />
                </div>
                {currentSegment && (
                    <div style={{ color: '#888', fontSize: '11px', marginBottom: '8px' }}>
                        Now playing: {currentSegment.video.title || currentSegment.video.url.split('/').pop()}<br />
                        Segment: {currentSegment.start.toFixed(1)}s – {currentSegment.end.toFixed(1)}s
                    </div>
                )}
            </>
        )}

        <button className="gold-outline-btn" onClick={onUploadVideoTrigger} style={{ width: '100%', marginBottom: '10px' }}>Upload Video</button>
        <label style={{ display: 'flex', alignItems: 'center', color: '#a0a0b0', fontSize: '13px' }}>
            <input
                type="checkbox"
                className="gold-checkbox"
                checked={isMuted}
                onChange={(e) => setIsMuted(e.target.checked)}
                style={{ marginRight: '8px' }}
            /> Mute Audio
        </label>
    </div>
);

export default VideoSourcePanel;
