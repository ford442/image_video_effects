import React from 'react';
import { InputSource } from './renderer/types';

export function RemoteControlHeader({
    inputSource,
    onLoadRandom,
}: {
    inputSource: InputSource;
    onLoadRandom: () => void;
}) {
    return (
        <h2 className="remote-app-header" style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '16px',
            flexWrap: 'wrap',
            textAlign: 'center',
            padding: '16px 12px',
            margin: 0,
            backgroundColor: '#2a2a2a',
            borderBottom: '1px solid #444',
            flexShrink: 0
        }}>
            Remote Control
            <button
                type="button"
                className="toggle-sidebar-btn header-action-btn"
                onClick={onLoadRandom}
                title="Load a random image from the manifest"
                disabled={inputSource !== 'image'}
            >
                🎲 Random Image
            </button>
        </h2>
    );
}
