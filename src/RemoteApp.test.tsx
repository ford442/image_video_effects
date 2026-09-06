import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import RemoteApp from './RemoteApp';
import { FullState } from './syncTypes';

jest.mock('./components/Controls', () => {
  const React = require('react');
  return {
    __esModule: true,
    default: function ControlsStub() {
      return React.createElement(
        'div',
        { 'data-testid': 'controls' },
        React.createElement('input', { type: 'text', 'aria-label': 'set name' }),
      );
    },
  };
});

class MockBroadcastChannel {
  static instances: MockBroadcastChannel[] = [];
  name: string;
  onmessage: ((ev: MessageEvent) => void) | null = null;

  constructor(name: string) {
    this.name = name;
    MockBroadcastChannel.instances.push(this);
  }

  postMessage() {}

  close() {
    const idx = MockBroadcastChannel.instances.indexOf(this);
    if (idx >= 0) MockBroadcastChannel.instances.splice(idx, 1);
  }
}

const DEFAULT_SLOT = {
  zoomParam1: 0.5, zoomParam2: 0.5, zoomParam3: 0.5, zoomParam4: 0.5,
  lightStrength: 1.0, ambient: 0.2, normalStrength: 0.1, fogFalloff: 4.0, depthThreshold: 0.5,
};

function fullState(overrides: Partial<FullState> = {}): FullState {
  return {
    modes: ['liquid', 'none', 'none'],
    activeSlot: 0,
    slotParams: [{ ...DEFAULT_SLOT }, { ...DEFAULT_SLOT }, { ...DEFAULT_SLOT }],
    shaderCategory: 'image',
    inputSource: 'image',
    autoChangeEnabled: false,
    autoChangeDelay: 10,
    isModelLoaded: false,
    availableModes: [],
    videoList: [],
    selectedVideo: '',
    isMuted: true,
    ...overrides,
  };
}

function connect(overrides: Partial<FullState> = {}) {
  const remote = MockBroadcastChannel.instances[0];
  act(() => {
    remote.onmessage?.({
      data: { type: 'STATE_FULL', payload: fullState(overrides) },
    } as MessageEvent);
  });
}

function setSearch(search: string, hash = '') {
  Object.defineProperty(window, 'location', {
    value: {
      pathname: '/',
      search,
      hash,
      hostname: 'localhost',
      href: `http://localhost/${search}${hash}`,
    },
    configurable: true,
  });
}

describe('RemoteApp chrome', () => {
  const originalLocation = window.location;
  const originalBC = global.BroadcastChannel;
  let replaceState: jest.SpyInstance;

  beforeEach(() => {
    jest.useFakeTimers();
    MockBroadcastChannel.instances = [];
    // @ts-expect-error test mock
    global.BroadcastChannel = MockBroadcastChannel;
    setSearch('?mode=remote');
    replaceState = jest.spyOn(window.history, 'replaceState').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.useRealTimers();
    replaceState.mockRestore();
    global.BroadcastChannel = originalBC;
    Object.defineProperty(window, 'location', { value: originalLocation, configurable: true });
  });

  it('shows header and no restore strip when chrome is visible', () => {
    render(<RemoteApp />);
    connect();
    expect(screen.getByRole('heading', { name: /remote control/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /random image/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /show controls/i })).not.toBeInTheDocument();
    expect(document.querySelector('.show-controls-overlay')).toBeNull();
  });

  it('seeds hidden chrome from chrome=hide', () => {
    setSearch('?mode=remote&chrome=hide');
    render(<RemoteApp />);
    connect();
    expect(screen.queryByRole('heading', { name: /remote control/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /random image/i })).not.toBeInTheDocument();
    const strip = screen.getByRole('button', { name: /show controls/i });
    expect(strip).toHaveClass('remote-chrome-restore');
    expect(document.querySelector('.remote-app.chrome-hidden')).toBeTruthy();
  });

  it('hides header and writes chrome=hide, then restore strip brings it back', () => {
    render(<RemoteApp />);
    connect();
    fireEvent.click(screen.getByRole('button', { name: /hide controls/i }));
    expect(screen.queryByRole('heading', { name: /remote control/i })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /show controls/i })).toBeInTheDocument();
    expect(replaceState).toHaveBeenCalledWith(null, '', '/?mode=remote&chrome=hide');

    fireEvent.click(screen.getByRole('button', { name: /show controls/i }));
    expect(screen.getByRole('heading', { name: /remote control/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /show controls/i })).not.toBeInTheDocument();
    expect(replaceState).toHaveBeenCalledWith(null, '', '/?mode=remote');
  });

  it('restores chrome on Escape', () => {
    render(<RemoteApp />);
    connect();
    fireEvent.click(screen.getByRole('button', { name: /hide controls/i }));
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(screen.getByRole('heading', { name: /remote control/i })).toBeInTheDocument();
  });

  it('does not restore chrome on Escape while a text input is focused', () => {
    render(<RemoteApp />);
    connect();
    fireEvent.click(screen.getByRole('button', { name: /hide controls/i }));
    const input = screen.getByLabelText('set name');
    input.focus();
    fireEvent.keyDown(input, { key: 'Escape' });
    expect(screen.queryByRole('heading', { name: /remote control/i })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /show controls/i })).toBeInTheDocument();
  });

  it('keeps Random Image disabled when inputSource is not image', () => {
    render(<RemoteApp />);
    connect({ inputSource: 'video' });
    expect(screen.getByRole('button', { name: /random image/i })).toBeDisabled();
  });
});
