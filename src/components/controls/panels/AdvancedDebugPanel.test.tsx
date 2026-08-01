import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { AdvancedDebugPanel } from './AdvancedDebugPanel';

test('renders coordinate browser button and fires onOpenCoordinateBrowser', () => {
    const onOpenCoordinateBrowser = jest.fn();

    render(
        <AdvancedDebugPanel
            onOpenCoordinateBrowser={onOpenCoordinateBrowser}
        />
    );

    fireEvent.click(screen.getByText(/Browse by Coordinate/));
    expect(onOpenCoordinateBrowser).toHaveBeenCalledTimes(1);
});

test('fires onOpenStorageBrowser when storage entry is shown', () => {
    const onOpenStorageBrowser = jest.fn();

    render(
        <AdvancedDebugPanel
            onOpenCoordinateBrowser={() => {}}
            onOpenStorageBrowser={onOpenStorageBrowser}
        />
    );

    fireEvent.click(screen.getByText(/VPS Storage Browser/));
    expect(onOpenStorageBrowser).toHaveBeenCalledTimes(1);
});

test('renders renderer diagnostics without requiring the console', () => {
    render(
        <AdvancedDebugPanel
            onOpenCoordinateBrowser={() => {}}
            diagnostics={{
                backend: 'wasm',
                fps: 58.4,
                adapterInfo: 'nvidia | turing | RTX 2060',
                wasmInitSummary: 'ready · adapter: nvidia | turing | RTX 2060',
            }}
        />
    );

    const block = screen.getByTestId('renderer-diagnostics');
    expect(block).toHaveTextContent('backend: wasm (experimental)');
    expect(block).toHaveTextContent('58 FPS');
    expect(block).toHaveTextContent('adapter: nvidia | turing | RTX 2060');
    expect(block).toHaveTextContent('wasm init: ready');
});

test('shows a WASM init error while running on the WebGPU fallback', () => {
    render(
        <AdvancedDebugPanel
            onOpenCoordinateBrowser={() => {}}
            diagnostics={{
                backend: 'webgpu',
                adapterInfo: 'intel | gen12 | Iris Xe',
                adapterAttemptLabel: 'high-performance',
                wasmInitSummary: 'partial at Surface · adapter: intel | gen12 | Iris Xe',
                wasmAdapterInfo: 'intel | gen12 | Iris Xe',
                wasmLastInitError: 'wgpuSurfaceConfigure failed',
            }}
        />
    );

    const block = screen.getByTestId('renderer-diagnostics');
    expect(block).toHaveTextContent('adapter ladder: high-performance');
    expect(block).toHaveTextContent('wasm init: partial at Surface');
    expect(block).toHaveTextContent('wasm error: wgpuSurfaceConfigure failed');
});

test('omits the diagnostics block when no diagnostics are provided', () => {
    render(<AdvancedDebugPanel onOpenCoordinateBrowser={() => {}} />);
    expect(screen.queryByTestId('renderer-diagnostics')).toBeNull();
});
