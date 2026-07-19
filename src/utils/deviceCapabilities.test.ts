import { isMobileTouchDevice, shouldShowMidiControls } from './deviceCapabilities';

describe('deviceCapabilities', () => {
  const originalMatchMedia = window.matchMedia;

  afterEach(() => {
    window.matchMedia = originalMatchMedia;
  });

  it('detects mobile touch via coarse pointer', () => {
    window.matchMedia = jest.fn().mockImplementation((query: string) => ({
      matches: query.includes('pointer: coarse'),
      media: query,
      addListener: jest.fn(),
      removeListener: jest.fn(),
    })) as typeof window.matchMedia;

    expect(isMobileTouchDevice()).toBe(true);
    expect(shouldShowMidiControls()).toBe(false);
  });

  it('shows MIDI on desktop when API available', () => {
    window.matchMedia = jest.fn().mockImplementation(() => ({
      matches: false,
      media: '',
      addListener: jest.fn(),
      removeListener: jest.fn(),
    })) as typeof window.matchMedia;

    Object.defineProperty(navigator, 'requestMIDIAccess', {
      value: jest.fn(),
      configurable: true,
    });

    expect(shouldShowMidiControls()).toBe(true);
  });
});
