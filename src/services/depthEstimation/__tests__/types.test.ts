import {
  normalizeDepthMap,
  depthTensorHeightWidth,
  classifyDepthLoadError,
} from '../types';

describe('depthEstimation/types', () => {
  describe('depthTensorHeightWidth', () => {
    it('reads height/width from trailing dims', () => {
      expect(depthTensorHeightWidth([1, 384, 512])).toEqual({ height: 384, width: 512 });
      expect(depthTensorHeightWidth([256, 128])).toEqual({ height: 256, width: 128 });
    });

    it('throws on invalid dims', () => {
      expect(() => depthTensorHeightWidth([1])).toThrow(/at least 2-D/);
    });
  });

  describe('normalizeDepthMap', () => {
    it('inverts min-max normalized depth to 0–1 Float32Array', () => {
      const map = normalizeDepthMap({
        dims: [2, 2],
        data: [0, 5, 10, 2.5],
      });
      expect(map.width).toBe(2);
      expect(map.height).toBe(2);
      expect(map.data).toBeInstanceOf(Float32Array);
      expect(map.data[0]).toBeCloseTo(1.0);
      expect(map.data[2]).toBeCloseTo(0.0);
      expect(map.data[1]).toBeCloseTo(0.5);
    });
  });

  describe('classifyDepthLoadError', () => {
    it('maps network failures to offline phase', () => {
      const result = classifyDepthLoadError(new Error('Failed to fetch'));
      expect(result.phase).toBe('offline');
      expect(result.message).toMatch(/blocked/i);
    });

    it('maps abort to cancelled', () => {
      const result = classifyDepthLoadError(new DOMException('Aborted', 'AbortError'));
      expect(result.phase).toBe('cancelled');
    });
  });
});
