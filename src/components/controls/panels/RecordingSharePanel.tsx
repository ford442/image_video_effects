import React from 'react';

export interface RecordingSharePanelProps {
    isRecording: boolean;
    recordingCountdown: number;
    onStartRecording?: () => void;
    onStopRecording?: () => void;
    onTakeScreenshot?: () => void;
}

export const RecordingSharePanel: React.FC<RecordingSharePanelProps> = ({
    isRecording,
    recordingCountdown,
    onStartRecording,
    onStopRecording,
    onTakeScreenshot,
}) => (
    <div className="glass-panel" style={{ padding: '15px', marginBottom: '15px' }}>
        <button
            onClick={isRecording ? onStopRecording : onStartRecording}
            className={`record-btn-gold ${isRecording ? 'recording' : ''}`}
            disabled={isRecording && recordingCountdown <= 0}
        >
            {isRecording ? (
                <>
                    <span>⏹️</span>
                    <span>Recording {recordingCountdown}s</span>
                    <span className="gold-spinner"></span>
                </>
            ) : (
                <>
                    <span>⏺️</span>
                    <span>Record 8s Clip</span>
                </>
            )}
        </button>

        {onTakeScreenshot && (
            <button
                type="button"
                onClick={onTakeScreenshot}
                className="gold-outline-btn"
                style={{ width: '100%', marginTop: '10px' }}
                disabled={isRecording}
            >
                📸 Save Screenshot
            </button>
        )}

        {isRecording && (
            <div style={{ marginTop: '10px', height: '4px', background: 'rgba(255,255,255,0.1)', borderRadius: '2px', overflow: 'hidden' }}>
                <div
                    style={{
                        height: '100%',
                        background: 'linear-gradient(90deg, #FFD700, #D4AF37)',
                        transition: 'width 0.3s ease',
                        width: `${((8 - recordingCountdown) / 8) * 100}%`,
                    }}
                />
            </div>
        )}

        <div style={{ fontSize: '11px', color: '#a0a0b0', textAlign: 'center', marginTop: '8px' }}>
            Capture & share your creation
        </div>
    </div>
);

export default RecordingSharePanel;
