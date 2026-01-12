import React from 'react';
import { render, screen } from '@testing-library/react';
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
    expect(screen.getByText(/Rain Speed:/)).toBeInTheDocument();
    expect(screen.getByText(/Rain Density:/)).toBeInTheDocument();
    expect(screen.getByText(/Wind:/)).toBeInTheDocument();
    expect(screen.getByText(/Splash\/Flow:/)).toBeInTheDocument();
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
