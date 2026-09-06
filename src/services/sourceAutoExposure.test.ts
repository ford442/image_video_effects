import { loadSourceAutoExposure, saveSourceAutoExposure } from './sourceAutoExposure';

describe('sourceAutoExposure persistence', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('defaults off', () => {
    expect(loadSourceAutoExposure()).toBe(false);
  });

  it('round-trips the opt-in flag', () => {
    saveSourceAutoExposure(true);
    expect(loadSourceAutoExposure()).toBe(true);
    saveSourceAutoExposure(false);
    expect(loadSourceAutoExposure()).toBe(false);
  });
});
