import React from 'react';
import { RendererSwitcher } from '../../RendererSwitcher';

export interface RendererBackendPanelProps {
    activeRendererType: 'webgpu' | 'wasm' | 'js';
    onSwitchRenderer: (type: 'webgpu' | 'wasm' | 'js') => Promise<void>;
}

export const RendererBackendPanel: React.FC<RendererBackendPanelProps> = ({
    activeRendererType,
    onSwitchRenderer,
}) => (
    <RendererSwitcher
        activeRendererType={activeRendererType}
        onSwitchRenderer={onSwitchRenderer}
    />
);

export default RendererBackendPanel;
