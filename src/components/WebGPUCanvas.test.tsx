import React from 'react';
import { render, fireEvent, screen } from '@testing-library/react';
import WebGPUCanvas from './WebGPUCanvas';

// Mock the Renderer class to prevent WebGPU initialization in tests
jest.mock('../renderer/Renderer', () => {
    return {
        Renderer: class {
            init = jest.fn().mockResolvedValue(true);
            render = jest.fn();
            destroy = jest.fn();
            setInputSource = jest.fn();
            addRipplePoint = jest.fn();
            firePlasma = jest.fn();
            getAvailableModes = () => [
                { id: 'interactive-ripple', features: ['mouse-driven'] }
            ];
        }
    };
});

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
    const mockRenderer: any = {
        getAvailableModes: () => [
            { id: 'interactive-ripple', features: ['mouse-driven'] }
        ],
        addRipplePoint: jest.fn(),
        setInputSource: jest.fn(),
        firePlasma: jest.fn(),
        render: jest.fn(),
    };

    const rendererRef = { current: mockRenderer } as any;
    const setMousePosition = jest.fn();
    const setIsMouseDown = jest.fn();

    render(
        <WebGPUCanvas
            modes={['interactive-ripple', 'none', 'none']}
            slotParams={[{}, {}, {}] as any}
            zoom={1}
            panX={0}
            panY={0}
            rendererRef={rendererRef as any}
            farthestPoint={{ x: 0.5, y: 0.5 }}
            mousePosition={{ x: -1, y: -1 }}
            setMousePosition={setMousePosition}
            isMouseDown={false}
            setIsMouseDown={setIsMouseDown}
            isMuted={false}
            inputSource={'image'}
            selectedVideo={''}
            apiBaseUrl={''}
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