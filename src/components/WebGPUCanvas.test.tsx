import React from 'react';
import { render, fireEvent } from '@testing-library/react';
import WebGPUCanvas from './WebGPUCanvas';

test('mouse down emits ripple for mouse-driven shader', () => {
    const mockRenderer: any = {
        getAvailableModes: () => [
            { id: 'interactive-ripple', features: ['mouse-driven'] }
        ],
        addRipplePoint: jest.fn(),
    };

    const rendererRef = { current: mockRenderer } as any;
    const setMousePosition = jest.fn();
    const setIsMouseDown = jest.fn();

    const { container } = render(
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
            inputSource={'image'}
            selectedVideo={''}
            apiBaseUrl={''}
        />
    );

    const canvas = container.querySelector('canvas')! as HTMLCanvasElement;
    // Simulate a bounding rect so normalized coords are predictable
    const rect = { left: 0, top: 0, width: 200, height: 200, right: 200, bottom: 200 } as DOMRect;
    // @ts-ignore - jsdom doesn't implement getBoundingClientRect the same way
    canvas.getBoundingClientRect = () => rect;

    fireEvent.mouseDown(canvas, { clientX: 100, clientY: 50 });

    // Expect addRipplePoint called with normalized coords (0.5, 0.25)
    expect(mockRenderer.addRipplePoint).toHaveBeenCalledWith(0.5, 0.25);
});