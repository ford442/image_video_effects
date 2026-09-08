import React from 'react';
import { InputSource } from './renderer/types';

export function RemoteControlHeader({
    inputSource,
    onLoadRandom,
    hidden,
    onHide,
}: {
    inputSource: InputSource;
    onLoadRandom: () => void;
    hidden: boolean;
    onHide: () => void;
}) {
    if (hidden) {
        return null;
    }

    return (
        <h2 className="remote-app-header">
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
            <button
                type="button"
                className="toggle-sidebar-btn"
                onClick={onHide}
                title="Hide titlebar and random-image control"
            >
                Hide Controls
            </button>
        </h2>
    );
}
