import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import Controls from './Controls';
import { ShaderEntry, SlotParams } from '../renderer/types';

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
            zoom={1} setZoom={() => {}}
            panX={0} setPanX={() => {}}
            panY={0} setPanY={() => {}}
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
            zoom={1} setZoom={() => {}}
            panX={0} setPanX={() => {}}
            panY={0} setPanY={() => {}}
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

test('filters slot mega-menu to non-generative or generative shaders based on effect filter', () => {
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
            zoom={1} setZoom={() => {}}
            panX={0} setPanX={() => {}}
            panY={0} setPanY={() => {}}
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

    fireEvent.click(screen.getByRole('button', { name: /liquid/i }));
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
            zoom={1} setZoom={() => {}}
            panX={0} setPanX={() => {}}
            panY={0} setPanY={() => {}}
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
    expect(screen.getByText('Gen Orb')).toBeInTheDocument();
    expect(screen.queryByText('Paint Flow')).not.toBeInTheDocument();
});
