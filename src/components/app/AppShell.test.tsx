import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { AppShell, AppShellProps } from './AppShell';
import { isPublicPixelocityHost } from '../../utils/publicHost';

jest.mock('../WebGPUCanvas', () => () => <div data-testid="canvas-stub" />);
jest.mock('../Controls', () => () => <div data-testid="controls-stub" />);
jest.mock('../../utils/publicHost', () => ({
  isPublicPixelocityHost: jest.fn(() => false),
}));

const mockedIsPublic = isPublicPixelocityHost as jest.MockedFunction<typeof isPublicPixelocityHost>;

function baseProps(overrides: Partial<AppShellProps> = {}): AppShellProps {
  const noop = () => {};
  const asyncNoop = async () => {};
  return {
    activeTab: 'main',
    setActiveTab: noop,
    showSidebar: true,
    setShowSidebar: noop,
    modes: ['none', 'none', 'none'],
    setMode: noop,
    activeSlot: 0,
    setActiveSlot: noop,
    slotParams: [],
    updateSlotParam: noop,
    slotShaderStatus: ['idle', 'idle', 'idle', 'idle', 'idle', 'idle'],
    shaderCategory: 'image',
    setShaderCategory: noop,
    handleNewRandomImage: noop,
    autoChangeEnabled: false,
    setAutoChangeEnabled: noop,
    autoChangeDelay: 10,
    setAutoChangeDelay: noop,
    loadDepthModel: noop,
    isModelLoaded: false,
    availableModes: [],
    inputSource: 'image',
    syncInputSourceToRenderer: noop,
    videoList: [],
    selectedVideo: '',
    setSelectedVideo: noop,
    videoB3hdMode: false,
    setVideoB3hdMode: noop,
    b3hdSegmentLength: 0,
    setB3hdSegmentLength: noop,
    b3hdIntervalSeconds: 0,
    setB3hdIntervalSeconds: noop,
    currentSegment: null,
    isMuted: true,
    setIsMuted: noop,
    activeGenerativeShader: '',
    setActiveGenerativeShader: noop,
    fileInputImageRef: { current: null },
    fileInputVideoRef: { current: null },
    isAiVjMode: false,
    toggleAiVj: noop,
    aiVjStatus: 'idle',
    aiVjMessage: '',
    handleGenerateFromVibe: noop,
    handleUpdateStack: noop,
    handleUpdateParams: noop,
    handleRandomizeParams: noop,
    handleSavePreset: noop,
    handleTriggerNextTransition: noop,
    handleRandomizeSlot: noop,
    handleSetSlotParam: noop,
    handleShareVjSet: noop,
    handleSaveVjSet: noop,
    startAutoTransition: async () => false,
    stopAutoTransition: noop,
    isWebcamActive: false,
    startWebcam: noop,
    stopWebcam: noop,
    webcamError: null,
    showWebcamShaderSuggestions: false,
    webcamFunShaders: [],
    applyWebcamFunShader: noop,
    triggerRoulette: noop,
    triggerRandomizeAllSlots: noop,
    isRouletteActive: false,
    chaosModeEnabled: false,
    setChaosModeEnabled: noop,
    audioReactiveParams: false,
    setAudioReactiveParams: noop,
    audioReactiveAmount: 0.8,
    setAudioReactiveAmount: noop,
    isRecording: false,
    recordingCountdown: 8,
    startRecording: noop,
    stopRecording: noop,
    handleTakeScreenshot: noop,
    setShowShaderScanner: noop,
    activeRendererType: 'webgpu',
    handleSwitchRenderer: asyncNoop,
    setShowStorageBrowser: noop,
    copyChainShareLink: noop,
    applySharedChain: noop,
    getCurrentChain: () => null,
    rendererRef: { current: null },
    mousePosition: { x: 0.5, y: 0.5 },
    setMousePosition: noop,
    isMouseDown: false,
    setIsMouseDown: noop,
    onInitCanvas: noop,
    videoSourceUrl: undefined,
    webgpuCanvasRef: { current: null },
    videoElementRef: { current: null },
    status: 'ready',
    generativeShowcaseActive: false,
    generativeShowcaseLocked: false,
    generativeShowcaseDelay: 12,
    onStartGenerativeShowcase: noop,
    onStopGenerativeShowcase: noop,
    onSetGenerativeShowcaseDelay: noop,
    onPreviewImportShader: noop,
    onImportStatus: noop,
    isRendererSwitching: false,
    jsFps: 0,
    wasmFps: 0,
    renderQualityMode: 'balanced',
    onRenderQualityChange: noop,
    sourceAutoExposure: false,
    onSourceAutoExposureChange: noop,
    performanceHud: {
      internalWidth: 1280,
      internalHeight: 720,
      scale: 1,
      targetFps: 60,
      adaptive: true,
      maxActiveSlots: 3,
    },
    ...overrides,
  } as AppShellProps;
}

describe('AppShell chrome', () => {
  beforeEach(() => {
    mockedIsPublic.mockReturnValue(false);
  });

  it('hides header and shows overlay when controls are hidden', () => {
    const setShowSidebar = jest.fn();
    render(<AppShell {...baseProps({ showSidebar: false, setShowSidebar })} />);

    expect(screen.queryByAltText('Pixelocity')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /random image/i })).not.toBeInTheDocument();
    // eslint-disable-next-line testing-library/no-node-access -- asserting CSS state classes, no accessible query exists
    expect(document.querySelector('.main-container.fullscreen')).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: /show controls/i }));
    expect(setShowSidebar).toHaveBeenCalledWith(true);
  });

  it('hides Open Remote on the public host', () => {
    mockedIsPublic.mockReturnValue(true);
    render(<AppShell {...baseProps()} />);
    expect(screen.queryByRole('button', { name: /open remote/i })).not.toBeInTheDocument();
  });

  it('shows Open Remote on non-public hosts', () => {
    render(<AppShell {...baseProps()} />);
    expect(screen.getByRole('button', { name: /open remote/i })).toBeInTheDocument();
  });
});

describe('AppShell renderer pill (WASM frozen R&D, #1080)', () => {
  beforeEach(() => {
    mockedIsPublic.mockReturnValue(false);
  });

  afterEach(() => {
    window.history.replaceState(null, '', '/');
  });

  it('is display-only and shows no R&D badge by default', () => {
    const handleSwitchRenderer = jest.fn(async () => {});
    render(<AppShell {...baseProps({ handleSwitchRenderer })} />);

    const pill = screen.getByText('🔷 WebGPU');
    fireEvent.click(pill);
    expect(handleSwitchRenderer).not.toHaveBeenCalled();
    expect(screen.queryByText('Experimental (R&D)')).not.toBeInTheDocument();
  });

  it('shows the Experimental (R&D) badge only when WASM is forced via ?renderer=wasm', () => {
    window.history.replaceState(null, '', '/?renderer=wasm');
    render(<AppShell {...baseProps({ activeRendererType: 'wasm' })} />);
    expect(screen.getByText('Experimental (R&D)')).toBeInTheDocument();
  });

  it('shows no R&D badge when WASM is active without the URL override', () => {
    render(<AppShell {...baseProps({ activeRendererType: 'wasm' })} />);
    expect(screen.queryByText('Experimental (R&D)')).not.toBeInTheDocument();
  });
});
