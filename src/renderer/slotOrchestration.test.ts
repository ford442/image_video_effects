import {
  resolveShaderBackend,
  setSlotParams,
  syncAllSlotParams,
  SLOT_COUNT,
} from './slotOrchestration';
import { SlotParams } from './types';

describe('slotOrchestration', () => {
  const defaultSlotParams: SlotParams = {
    zoomParam1: 0.1,
    zoomParam2: 0.2,
    zoomParam3: 0.3,
    zoomParam4: 0.4,
    lightStrength: 1,
    ambient: 0.2,
    normalStrength: 0.1,
    fogFalloff: 4,
    depthThreshold: 0.5,
  };

  it('resolves duck-typed shader backends', () => {
    const backend = {
      loadShader: jest.fn(),
      setActiveShader: jest.fn(),
      setSlotShader: jest.fn(),
      updateSlotParams: jest.fn(),
      setSlotMode: jest.fn(),
      addRipple: jest.fn(),
      clearRipples: jest.fn(),
    };
    expect(resolveShaderBackend(backend as never)).toBe(backend);
    expect(resolveShaderBackend(null)).toBeNull();
  });

  it('forwards setSlotParams via setSlotParams when available', () => {
    const backend = {
      loadShader: jest.fn(),
      setActiveShader: jest.fn(),
      setSlotShader: jest.fn(),
      setSlotParams: jest.fn(),
      updateSlotParams: jest.fn(),
      setSlotMode: jest.fn(),
      addRipple: jest.fn(),
      clearRipples: jest.fn(),
    };
    setSlotParams(backend, 1, 0.1, 0.2, 0.3, 0.4);
    expect(backend.setSlotParams).toHaveBeenCalledWith(1, 0.1, 0.2, 0.3, 0.4);
  });

  it('falls back to updateSlotParams aggregate form (#887)', () => {
    const backend = {
      loadShader: jest.fn(),
      setActiveShader: jest.fn(),
      setSlotShader: jest.fn(),
      updateSlotParams: jest.fn(),
      setSlotMode: jest.fn(),
      addRipple: jest.fn(),
      clearRipples: jest.fn(),
    };
    setSlotParams(backend, 0, 1, 2, 3, 4);
    expect(backend.updateSlotParams).toHaveBeenCalledWith(
      { zoomParam1: 1, zoomParam2: 2, zoomParam3: 3, zoomParam4: 4 },
      0,
    );
  });

  it('syncAllSlotParams pushes each slot index', () => {
    const backend = {
      loadShader: jest.fn(),
      setActiveShader: jest.fn(),
      setSlotShader: jest.fn(),
      updateSlotParams: jest.fn(),
      setSlotMode: jest.fn(),
      addRipple: jest.fn(),
      clearRipples: jest.fn(),
    };
    const slots = [
      { ...defaultSlotParams, zoomParam1: 0.11 },
      { ...defaultSlotParams, zoomParam2: 0.22 },
      { ...defaultSlotParams, zoomParam3: 0.33 },
    ];
    syncAllSlotParams(backend, slots, SLOT_COUNT);
    expect(backend.updateSlotParams).toHaveBeenCalledTimes(3);
    expect(backend.updateSlotParams).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ zoomParam1: 0.11 }),
      0,
    );
  });
});
