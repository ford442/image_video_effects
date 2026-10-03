import React from 'react';
import { render, fireEvent, screen, act } from '@testing-library/react';
import WebGPUCanvas, { waitForCanvasTeardown } from './WebGPUCanvas';
import { RendererManager } from '../renderer/RendererManager';
import { ShaderEntry, SlotParams } from '../renderer/types';

// Mock RendererManager + boot probe so no WebGPU initialization runs in tests.
// Plain functions, not jest.fn(): CRA's resetMocks would wipe factory implementations.
let mockReleaseGate: Promise<void> = Promise.resolve();
const mockEvents: string[] = [];

jest.mock('../renderer/RendererManager', () => ({
    getRendererTypeFromURL: () => null,
    RendererManager: class {
        init = async () => true;
        destroy = () => {
            mockEvents.push('destroy:start');
            return mockReleaseGate.then(() => { mockEvents.push('destroy:done'); });
        };
        setVideo = () => {};
        setInputSource = () => {};
        syncAllSlotParams = () => {};
        render = () => {};
        setParam = () => {};
        getDiagnostics = () => ({});
    },
}));

jest.mock('../renderer/webgpuBootProbe', () => ({
    runWebGpuBootProbe: async () => {
        mockEvents.push('probe');
        return { ok: true, handoff: {} };
    },
    publishWebGpuProbe: () => {},
    publishWasmProbeFailure: () => {},
    toWebGpuProbeBreadcrumb: (p: unknown) => p,
}));

beforeAll(() => {
    // Mock ResizeObserver
    global.ResizeObserver = class ResizeObserver {
        observe() {}
        unobserve() {}
        disconnect() {}
    };

    // Mock matchMedia
    Object.defineProperty(window, 'matchMedia', {
        writable: true,
        value: jest.fn().mockImplementation(query => ({
            matches: false,
            media: query,
            onchange: null,
            addListener: jest.fn(), // Deprecated
            removeListener: jest.fn(), // Deprecated
            addEventListener: jest.fn(),
            removeEventListener: jest.fn(),
            dispatchEvent: jest.fn(),
        })),
    });

    // Mock HTMLMediaElement methods
    Object.defineProperty(window.HTMLMediaElement.prototype, 'play', {
        writable: true,
        value: jest.fn().mockImplementation(() => Promise.resolve()),
    });
    Object.defineProperty(window.HTMLMediaElement.prototype, 'pause', {
        writable: true,
        value: jest.fn(),
    });
    Object.defineProperty(window.HTMLMediaElement.prototype, 'load', {
        writable: true,
        value: jest.fn(),
    });
});

test('mouse down emits ripple for mouse-driven shader', () => {
    const mockRenderer = {
        addRipplePoint: jest.fn(),
        firePlasma: jest.fn(),
        syncAllSlotParams: jest.fn(),
        setInputSource: jest.fn(),
        setVideo: jest.fn(),
        render: jest.fn(),
    };

    const rendererRef = { current: mockRenderer as unknown as RendererManager };
    const setMousePosition = jest.fn();
    const setIsMouseDown = jest.fn();

    render(
        <WebGPUCanvas
            modes={['interactive-ripple', 'none', 'none']}
            slotParams={[{}, {}, {}] as SlotParams[]}
            rendererRef={rendererRef}
            shaderCatalog={[
                { id: 'interactive-ripple', features: ['mouse-driven'] } as ShaderEntry,
            ]}
            farthestPoint={{ x: 0.5, y: 0.5 }}
            mousePosition={{ x: -1, y: -1 }}
            setMousePosition={setMousePosition}
            isMouseDown={false}
            setIsMouseDown={setIsMouseDown}
            isMuted={false}
            inputSource={'image'}
            selectedVideo={''}
            apiBaseUrl={''}
            activeSlot={0}
            activeGenerativeShader={undefined}
            setInputSource={() => {}}
        />
    );

    const canvas = screen.getByTestId('webgpu-canvas') as HTMLCanvasElement;
    // Simulate a bounding rect so normalized coords are predictable
    const rect = { left: 0, top: 0, width: 200, height: 200, right: 200, bottom: 200 } as DOMRect;
    // @ts-ignore - jsdom doesn't implement getBoundingClientRect the same way
    canvas.getBoundingClientRect = () => rect;

    fireEvent.mouseDown(canvas, { clientX: 100, clientY: 50 });

    // Expect addRipplePoint called with normalized coords (0.5, 0.25)
    expect(mockRenderer.addRipplePoint).toHaveBeenCalledWith(0.5, 0.25);
});

test('remount waits for the previous renderer teardown before re-probing', async () => {
    const rectSpy = jest.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue(
        { left: 0, top: 0, width: 200, height: 200, right: 200, bottom: 200, x: 0, y: 0, toJSON: () => ({}) } as DOMRect,
    );
    mockEvents.length = 0;
    let releaseFirst!: () => void;
    mockReleaseGate = new Promise<void>((resolve) => { releaseFirst = resolve; });

    const props = {
        modes: ['none'] as never,
        slotParams: [] as SlotParams[],
        farthestPoint: { x: 0.5, y: 0.5 },
        mousePosition: { x: -1, y: -1 },
        setMousePosition: jest.fn(),
        isMouseDown: false,
        setIsMouseDown: jest.fn(),
        isMuted: false,
        inputSource: 'image' as const,
        selectedVideo: '',
        apiBaseUrl: '',
        activeSlot: 0,
        setInputSource: () => {},
    };

    const view = render(<WebGPUCanvas {...props} rendererRef={{ current: null }} />);
    await act(async () => { await new Promise((r) => setTimeout(r, 0)); });
    expect(mockEvents).toEqual(['probe']);
    view.unmount();

    render(<WebGPUCanvas {...props} rendererRef={{ current: null }} />);
    await act(async () => { await new Promise((r) => setTimeout(r, 10)); });
    // The second mount must not request a device while the first is still releasing.
    expect(mockEvents).toEqual(['probe', 'destroy:start']);

    await act(async () => {
        releaseFirst();
        await waitForCanvasTeardown();
        await new Promise((r) => setTimeout(r, 0));
    });
    expect(mockEvents).toEqual(['probe', 'destroy:start', 'destroy:done', 'probe']);
    rectSpy.mockRestore();
});
