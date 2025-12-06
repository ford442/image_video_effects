import React from 'react';
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import Controls from './Controls';
import { ShaderEntry } from '../renderer/types';

const mockSetMode = jest.fn();
const mockSetShaderCategory = jest.fn();
const mockSetZoomParam1 = jest.fn();

const availableModes: ShaderEntry[] = [
    { id: 'rain', name: 'Rain', url: 'shaders/rain.wgsl', category: 'image' }
];

test('renders Rain controls when mode is rain', () => {
    render(
        <Controls
            mode="rain"
            setMode={mockSetMode}
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
            // Generic params
            zoomParam1={0.5} setZoomParam1={mockSetZoomParam1}
            zoomParam2={0.5} setZoomParam2={() => {}}
            zoomParam3={2.0} setZoomParam3={() => {}}
            zoomParam4={0.7} setZoomParam4={() => {}}
        />
    );

    // Check for Rain specific labels
    expect(screen.getByText(/Rain Speed:/)).toBeInTheDocument();
    expect(screen.getByText(/Rain Density:/)).toBeInTheDocument();
    expect(screen.getByText(/Wind:/)).toBeInTheDocument();
    expect(screen.getByText(/Splash\/Flow:/)).toBeInTheDocument();
});

test('does not render Rain controls when mode is not rain', () => {
    render(
        <Controls
            mode="liquid"
            setMode={mockSetMode}
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
             // Generic params
            zoomParam1={0.5} setZoomParam1={() => {}}
            zoomParam2={0.5} setZoomParam2={() => {}}
            zoomParam3={2.0} setZoomParam3={() => {}}
            zoomParam4={0.7} setZoomParam4={() => {}}
        />
    );

    expect(screen.queryByText(/Rain Speed:/)).not.toBeInTheDocument();
});
