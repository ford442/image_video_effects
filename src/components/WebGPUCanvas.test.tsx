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

// jsdom has no PointerEvent; without it fireEvent.pointerDown drops clientX/clientY.
if (typeof window.PointerEvent === 'undefined') {
    class JsdomPointerEvent extends MouseEvent {
        readonly pointerType: string;
        constructor(type: string, init: PointerEventInit = {}) {
            super(type, init);
            this.pointerType = init.pointerType ?? 'mouse';
        }
    }
    (window as unknown as { PointerEvent: typeof JsdomPointerEvent }).PointerEvent = JsdomPointerEvent;
}

test('one pointer down emits exactly one ripple for mouse, touch and pen (#1511 bug 5)', () => {
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

    // A real click dispatches pointerdown and then the compatibility mousedown.
    fireEvent.pointerDown(canvas, { clientX: 100, clientY: 50, pointerType: 'mouse' });
    fireEvent.mouseDown(canvas, { clientX: 100, clientY: 50 });

    // Exactly one ripple at normalized coords (0.5, 0.25): no double down-handler (#1511 bug 5).
    expect(mockRenderer.addRipplePoint).toHaveBeenCalledTimes(1);
    expect(mockRenderer.addRipplePoint).toHaveBeenCalledWith(0.5, 0.25);
    expect(setIsMouseDown).toHaveBeenCalledTimes(1);

    // Touch and pen arrive through the same pointer handler.
    fireEvent.pointerDown(canvas, { clientX: 50, clientY: 100, pointerType: 'touch' });
    fireEvent.pointerDown(canvas, { clientX: 150, clientY: 150, pointerType: 'pen' });
    expect(mockRenderer.addRipplePoint).toHaveBeenCalledTimes(3);
    expect(mockRenderer.addRipplePoint).toHaveBeenLastCalledWith(0.75, 0.75);
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
