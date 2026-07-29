import React from 'react';

import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import { ControlsContainer as Controls } from "./controls/ControlsContainer";
import { ShaderEntry, SlotParams } from '../renderer/types';

// Setup matchMedia mock early
beforeAll(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: jest.fn(),
      removeListener: jest.fn(),
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
    })),
  });
});

beforeEach(() => {
    localStorage.clear();
});

const mockSetMode = jest.fn();
const mockSetShaderCategory = jest.fn();
const mockSetActiveSlot = jest.fn();
const mockUpdateSlotParam = jest.fn();

const availableModes: ShaderEntry[] = [
    {
        id: 'rain',
        name: 'Rain',
        url: 'shaders/rain.wgsl',
        category: 'image',
        params: [
            { id: 'speed', name: 'Rain Speed', default: 0.5, min: 0, max: 1 },
            { id: 'density', name: 'Rain Density', default: 0.5, min: 0, max: 1 },
            { id: 'wind', name: 'Wind', default: 0.5, min: 0, max: 1 },
            { id: 'splash', name: 'Splash/Flow', default: 0.5, min: 0, max: 1 }
        ]
    },
    { id: 'liquid', name: 'Liquid', url: 'shaders/liquid.wgsl', category: 'image' }
];

const defaultSlotParams: SlotParams = {
    zoomParam1: 0.5,
    zoomParam2: 0.5,
    zoomParam3: 0.5,
    zoomParam4: 0.5,
    lightStrength: 1.0,
    ambient: 0.2,
    normalStrength: 0.1,
    fogFalloff: 4.0,
    depthThreshold: 0.5
};

const mockSlotParams = [defaultSlotParams, defaultSlotParams, defaultSlotParams];

test('renders Rain controls when active slot mode is rain', () => {
    render(
        <Controls
            modes={['rain', 'none', 'none']}
            setMode={mockSetMode}
            activeSlot={0}
            setActiveSlot={mockSetActiveSlot}
            slotParams={mockSlotParams}
            updateSlotParam={mockUpdateSlotParam}
            shaderCategory="image"
            setShaderCategory={mockSetShaderCategory}
            onNewImage={() => {}}
            autoChangeEnabled={false} setAutoChangeEnabled={() => {}}
            autoChangeDelay={10} setAutoChangeDelay={() => {}}
            onLoadModel={() => {}}
            isModelLoaded={false}
            availableModes={availableModes}
            inputSource="image" setInputSource={() => {}}
            videoList={[]} selectedVideo="" setSelectedVideo={() => {}}
            isMuted={false} setIsMuted={() => {}}
            onUploadImageTrigger={() => {}}
            onUploadVideoTrigger={() => {}}
            isAiVjMode={false}
            onToggleAiVj={() => {}}
            aiVjStatus={'idle'}
        />
    );

    // Check for Rain specific labels
    // The component now renders "Name: Value", so we look for the text start
    expect(screen.getByText(/Rain Speed/)).toBeInTheDocument();
    expect(screen.getByText(/Rain Density/)).toBeInTheDocument();
    expect(screen.getByText(/Wind/)).toBeInTheDocument();
    expect(screen.getByText(/Splash\/Flow/)).toBeInTheDocument();
});

test('does not render Rain controls when active slot mode is not rain', () => {
    render(
        <Controls
            modes={['liquid', 'none', 'none']}
            setMode={mockSetMode}
            activeSlot={0}
            setActiveSlot={mockSetActiveSlot}
            slotParams={mockSlotParams}
            updateSlotParam={mockUpdateSlotParam}
            shaderCategory="image"
            setShaderCategory={mockSetShaderCategory}
            onNewImage={() => {}}
            autoChangeEnabled={false} setAutoChangeEnabled={() => {}}
            autoChangeDelay={10} setAutoChangeDelay={() => {}}
            onLoadModel={() => {}}
            isModelLoaded={false}
            availableModes={availableModes}
            inputSource="image" setInputSource={() => {}}
            videoList={[]} selectedVideo="" setSelectedVideo={() => {}}
            isMuted={false} setIsMuted={() => {}}
            onUploadImageTrigger={() => {}}
            onUploadVideoTrigger={() => {}}
            isAiVjMode={false}
            onToggleAiVj={() => {}}
            aiVjStatus={'idle'}
        />
    );

    expect(screen.queryByText(/Rain Speed/)).not.toBeInTheDocument();
});

test.skip('filters slot mega-menu to non-generative or generative shaders based on effect filter', () => {
    const megaMenuModes: ShaderEntry[] = [
        { id: 'liquid', name: 'Liquid', url: 'shaders/liquid.wgsl', category: 'image' },
        { id: 'paint-flow', name: 'Paint Flow', url: 'shaders/paint-flow.wgsl', category: 'artistic' },
        { id: 'gen-orb', name: 'Gen Orb', url: 'shaders/gen-orb.wgsl', category: 'generative' }
    ];

    const { rerender } = render(
        <Controls
            modes={['liquid', 'none', 'none']}
            setMode={mockSetMode}
            activeSlot={0}
            setActiveSlot={mockSetActiveSlot}
            slotParams={mockSlotParams}
            updateSlotParam={mockUpdateSlotParam}
            shaderCategory="image"
            setShaderCategory={mockSetShaderCategory}
            onNewImage={() => {}}
            autoChangeEnabled={false} setAutoChangeEnabled={() => {}}
            autoChangeDelay={10} setAutoChangeDelay={() => {}}
            onLoadModel={() => {}}
            isModelLoaded={false}
            availableModes={megaMenuModes}
            inputSource="image" setInputSource={() => {}}
            videoList={[]} selectedVideo="" setSelectedVideo={() => {}}
            isMuted={false} setIsMuted={() => {}}
            onUploadImageTrigger={() => {}}
            onUploadVideoTrigger={() => {}}
            isAiVjMode={false}
            onToggleAiVj={() => {}}
            aiVjStatus={'idle'}
        />
    );

    fireEvent.click(screen.getAllByRole('button', { name: /liquid/i })[0]);
    expect(screen.getByText('Paint Flow')).toBeInTheDocument();
    expect(screen.queryByText('Gen Orb')).not.toBeInTheDocument();

    fireEvent.mouseDown(screen.getByText('Paint Flow'));

    rerender(
        <Controls
            modes={['gen-orb', 'none', 'none']}
            setMode={mockSetMode}
            activeSlot={0}
            setActiveSlot={mockSetActiveSlot}
            slotParams={mockSlotParams}
            updateSlotParam={mockUpdateSlotParam}
            shaderCategory="generative"
            setShaderCategory={mockSetShaderCategory}
            onNewImage={() => {}}
            autoChangeEnabled={false} setAutoChangeEnabled={() => {}}
            autoChangeDelay={10} setAutoChangeDelay={() => {}}
            onLoadModel={() => {}}
            isModelLoaded={false}
            availableModes={megaMenuModes}
            inputSource="image" setInputSource={() => {}}
            videoList={[]} selectedVideo="" setSelectedVideo={() => {}}
            isMuted={false} setIsMuted={() => {}}
            onUploadImageTrigger={() => {}}
            onUploadVideoTrigger={() => {}}
            isAiVjMode={false}
            onToggleAiVj={() => {}}
            aiVjStatus={'idle'}
        />
    );

    fireEvent.click(screen.getByRole('button', { name: /gen orb/i }));
    expect(screen.getAllByText('Gen Orb').length).toBeGreaterThan(0);
    expect(screen.queryByText('Paint Flow')).not.toBeInTheDocument();
});



describe('Live Control panel', () => {
    const baseProps = {
        modes: ['rain', 'none', 'none'] as string[],
        setMode: mockSetMode,
        activeSlot: 0,
        setActiveSlot: mockSetActiveSlot,
        slotParams: mockSlotParams,
        updateSlotParam: mockUpdateSlotParam,
        shaderCategory: 'image' as const,
        setShaderCategory: mockSetShaderCategory,
        onNewImage: () => {},
        autoChangeEnabled: false,
        setAutoChangeEnabled: () => {},
        autoChangeDelay: 10,
        setAutoChangeDelay: () => {},
        onLoadModel: () => {},
        isModelLoaded: false,
        availableModes,
        inputSource: 'image' as const,
        setInputSource: () => {},
        videoList: [],
        selectedVideo: '',
        setSelectedVideo: () => {},
        isMuted: false,
        setIsMuted: () => {},
        onUploadImageTrigger: () => {},
        onUploadVideoTrigger: () => {},
        isAiVjMode: false,
        onToggleAiVj: () => {},
        aiVjStatus: 'idle' as const,
        onTriggerNextTransition: jest.fn(),
        onRandomizeSlot: jest.fn(),
        onSetSlotParam: jest.fn(),
    };

    test('expands and captures a key binding', async () => {
        render(<Controls {...baseProps} />);

        // skipped VJ studio click
        expect(screen.getByText('Arm Key')).toBeInTheDocument();

        fireEvent.click(screen.getByText('Arm Key'));
        expect(screen.getByText('Press a key…')).toBeInTheDocument();

        fireEvent.keyDown(window, { key: 't' });

        await waitFor(() => {
            expect(screen.getByText(/Captured:/)).toBeInTheDocument();
        });

        fireEvent.click(screen.getByText('Save Binding'));

        await waitFor(() => {
            expect(screen.getByText(/Bindings \(1\)/)).toBeInTheDocument();
        });

        expect(screen.getByText('t')).toBeInTheDocument();
        expect(screen.getByText(/trigger transition/)).toBeInTheDocument();
    });

    test('clears a saved binding', async () => {
        render(<Controls {...baseProps} />);

        // skipped VJ studio click
        fireEvent.click(screen.getByText('Arm Key'));
        fireEvent.keyDown(window, { key: 'r' });

        await waitFor(() => {
            expect(screen.getByText(/Captured:/)).toBeInTheDocument();
        });

        fireEvent.click(screen.getByText('Save Binding'));
        await waitFor(() => {
            expect(screen.getByText(/Bindings \(1\)/)).toBeInTheDocument();
        });

        fireEvent.click(screen.getAllByText('✕')[0]);

        await waitFor(() => {
            expect(screen.queryByText(/Bindings/)).not.toBeInTheDocument();
        });
    });
});

describe('Community gallery wiring', () => {
    const chain = { v: 1 as const, slots: [{ shaderId: 'liquid-metal' }] };

    test('renders Community Gallery when chain sharing props are provided', () => {
        render(
            <Controls
                modes={['rain', 'none', 'none']}
                setMode={mockSetMode}
                activeSlot={0}
                setActiveSlot={mockSetActiveSlot}
                slotParams={mockSlotParams}
                updateSlotParam={mockUpdateSlotParam}
                shaderCategory="image"
                setShaderCategory={mockSetShaderCategory}
                onNewImage={() => {}}
                autoChangeEnabled={false}
                setAutoChangeEnabled={() => {}}
                autoChangeDelay={10}
                setAutoChangeDelay={() => {}}
                onLoadModel={() => {}}
                isModelLoaded={false}
                availableModes={availableModes}
                inputSource="image"
                setInputSource={() => {}}
                videoList={[]}
                selectedVideo=""
                setSelectedVideo={() => {}}
                isMuted={false}
                setIsMuted={() => {}}
                onUploadImageTrigger={() => {}}
                onUploadVideoTrigger={() => {}}
                isAiVjMode={false}
                onToggleAiVj={() => {}}
                aiVjStatus="idle"
                onApplySharedChain={jest.fn()}
                getCurrentChain={() => chain}
            />
        );

        expect(screen.getByText('Community Gallery')).toBeInTheDocument();
        expect(screen.getByText('Preset Packs')).toBeInTheDocument();
    });
});
