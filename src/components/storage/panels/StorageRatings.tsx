import { useCallback } from 'react';

interface RateShaderFn {
  (shaderId: string, rating: number): Promise<unknown>;
}

interface RefreshShadersFn {
  (): Promise<void>;
}

/** Rating seam — keeps star UI decoupled from StorageClient wiring in list panels. */
export function useShaderRating(rateShader: RateShaderFn, refreshShaders: RefreshShadersFn) {
  return useCallback(
    async (shaderId: string, rating: number) => {
      await rateShader(shaderId, rating);
      refreshShaders().catch(() => {});
    },
    [rateShader, refreshShaders],
  );
}
