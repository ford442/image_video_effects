import { render, fireEvent, screen, act } from '@testing-library/react';
import WebGPUCanvas, { waitForCanvasTeardown } from './WebGPUCanvas';
import { RendererManager } from '../renderer/RendererManager';
import { ShaderEntry, SlotParams } from '../renderer/types';

// Mock RendererManager + boot probe so no WebGPU initialization runs in tests.
// Plain functions, not vi.fn(): CRA's resetMocks would wipe factory implementations.
const mocks = vi.hoisted(() => ({ releaseGate: Promise.resolve() as Promise<void>, events: [] as string[] }));

vi.mock('../renderer/RendererManager', () => ({
    getRendererTypeFromURL: () => null,
    RendererManager: class {
        init = async () => true;
        destroy = () => {
            mocks.events.push('destroy:start');
            return mocks.releaseGate.then(() => { mocks.events.push('destroy:done'); });
        };
        setVideo = () => {};
        setInputSource = () => {};
        syncAllSlotParams = () => {};
        render() {}
        setParam = () => {};
        getDiagnostics = () => ({});
    },
}));

vi.mock('../renderer/webgpuBootProbe', () => ({
    runWebGpuBootProbe: async () => {
        mocks.events.push('probe');
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
        value: vi.fn().mockImplementation(query => ({
            matches: false,
            media: query,
            onchange: null,
            addListener: vi.fn(), // Deprecated
            removeListener: vi.fn(), // Deprecated
            addEventListener: vi.fn(),
            removeEventListener: vi.fn(),
            dispatchEvent: vi.fn(),
        })),
    });

    // Mock HTMLMediaElement methods
    Object.defineProperty(window.HTMLMediaElement.prototype, 'play', {
        writable: true,
        value: vi.fn().mockImplementation(() => Promise.resolve()),
    });
    Object.defineProperty(window.HTMLMediaElement.prototype, 'pause', {
        writable: true,
        value: vi.fn(),
    });
    Object.defineProperty(window.HTMLMediaElement.prototype, 'load', {
        writable: true,
        value: vi.fn(),
    });
});

test('pointer down emits exactly one ripple for mouse-driven shader', () => {
    const mockRenderer = {
        addRipplePoint: vi.fn(),
        firePlasma: vi.fn(),
        syncAllSlotParams: vi.fn(),
        setInputSource: vi.fn(),
        setVideo: vi.fn(),
        render: vi.fn(),
    };

    const rendererRef = { current: mockRenderer as unknown as RendererManager };
    const setMousePosition = vi.fn();
    const setIsMouseDown = vi.fn();

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

    // A real click dispatches pointerdown and then a compatibility mousedown;
    // only the pointer event may run the down handler (regression: double ripple).
    // jsdom's PointerEvent drops clientX/Y, so dispatch a MouseEvent typed pointerdown.
    act(() => {
        canvas.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, clientX: 100, clientY: 50 }));
    });
    fireEvent.mouseDown(canvas, { clientX: 100, clientY: 50 });

    // Expect addRipplePoint called once with normalized coords (0.5, 0.25)
    expect(mockRenderer.addRipplePoint).toHaveBeenCalledTimes(1);
    expect(mockRenderer.addRipplePoint).toHaveBeenCalledWith(0.5, 0.25);
});

test('remount waits for the previous renderer teardown before re-probing', async () => {
    const rectSpy = vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue(
        { left: 0, top: 0, width: 200, height: 200, right: 200, bottom: 200, x: 0, y: 0, toJSON: () => ({}) } as DOMRect,
    );
    mocks.events.length = 0;
    let releaseFirst!: () => void;
    mocks.releaseGate = new Promise<void>((resolve) => { releaseFirst = resolve; });

    const props = {
        modes: ['none'] as never,
        slotParams: [] as SlotParams[],
        farthestPoint: { x: 0.5, y: 0.5 },
        mousePosition: { x: -1, y: -1 },
        setMousePosition: vi.fn(),
        isMouseDown: false,
        setIsMouseDown: vi.fn(),
        isMuted: false,
        inputSource: 'image' as const,
        selectedVideo: '',
        apiBaseUrl: '',
        activeSlot: 0,
        setInputSource: () => {},
    };

    const view = render(<WebGPUCanvas {...props} rendererRef={{ current: null }} />);
    await act(async () => { await new Promise((r) => setTimeout(r, 0)); });
    expect(mocks.events).toEqual(['probe']);
    view.unmount();

    render(<WebGPUCanvas {...props} rendererRef={{ current: null }} />);
    await act(async () => { await new Promise((r) => setTimeout(r, 10)); });
    // The second mount must not request a device while the first is still releasing.
    expect(mocks.events).toEqual(['probe', 'destroy:start']);

    await act(async () => {
        releaseFirst();
        await waitForCanvasTeardown();
        await new Promise((r) => setTimeout(r, 0));
    });
    expect(mocks.events).toEqual(['probe', 'destroy:start', 'destroy:done', 'probe']);
    rectSpy.mockRestore();
});
