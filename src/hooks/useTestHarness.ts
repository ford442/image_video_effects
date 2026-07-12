import { useEffect, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';

export interface UseTestHarnessOptions {
    rendererRef: RefObject<RendererManager | null>;
    rendererReady: boolean;
}

export function useTestHarness({
    rendererRef,
    rendererReady,
}: UseTestHarnessOptions): void {
    useEffect(() => {
        if (typeof window === 'undefined') return;
        const params = new URLSearchParams(window.location.search);
        if (params.get('testMode') === '1' && rendererRef.current) {
            const manager = rendererRef.current;
            const loadShaderTracked = async (id: string, url: string) => {
                const ok = await manager.loadShader(id, url) ?? false;
                if (params.get('shaderHotReload') === '1') {
                    import('../dev/shaderHotReload').then(({ trackShaderForHotReload }) => {
                        trackShaderForHotReload(id, url);
                    });
                }
                return ok;
            };
            (window as unknown as { __pixelocity__: Record<string, unknown> }).__pixelocity__ = {
                renderer: manager,
                getRendererType: () => manager.getActiveRendererType(),
                setSlotShader: (index: number, id: string) => {
                    manager.setSlotShader(index, id);
                },
                loadShader: loadShaderTracked,
                reloadShader: (id: string, url: string) => manager.reloadShader(id, url),
                setInputSource: (source: Parameters<typeof manager.setInputSource>[0]) => {
                    manager.setInputSource(source);
                },
                setTestRenderState: (state: Parameters<typeof manager.applyTestRenderState>[0]) => {
                    manager.applyTestRenderState(state);
                },
                captureCanvasScreenshot: async () => {
                    const canvas = document.querySelector('canvas');
                    if (!canvas) return null;
                    return canvas.toDataURL('image/png');
                },
                runBenchmark: async (frameCount = 90) => {
                    const samples: Array<{ fps: number; gpu: ReturnType<typeof manager.getGPUTimings> }> = [];
                    for (let i = 0; i < frameCount; i++) {
                        await new Promise<void>((r) => requestAnimationFrame(() => r()));
                        samples.push({
                            fps: manager.getMetrics().fps,
                            gpu: manager.getGPUTimings(),
                        });
                    }
                    const totals = samples.map((s) => s.gpu.totalTime).filter((t) => t > 0);
                    const avgTotalMs = totals.length
                        ? totals.reduce((a, b) => a + b, 0) / totals.length
                        : 0;
                    return {
                        frames: frameCount,
                        avgFps: samples.reduce((a, s) => a + s.fps, 0) / frameCount,
                        avgTotalMs,
                        gpuTimingsAvailable: samples.some((s) => s.gpu.available),
                        rendererType: manager.getActiveRendererType(),
                        samples: samples.slice(-5),
                    };
                },
                updateAudioFrequencyBins: (bins: Float32Array) => {
                    manager.updateAudioFrequencyBins(bins);
                },
                getSlotState: (index: number) => manager.getSlotState(index),
                getGPUTimings: () => manager.getGPUTimings(),
                getSupportsDeepWorkgroup: () => manager.getSupportsDeepWorkgroup(),
                takeScreenshot: (filename?: string) => manager.takeScreenshot(filename),
                refreshFrameImage: () => manager.refreshFrameImage(),
                getFrameImage: () => manager.getFrameImage(),
            };
        }
    }, [rendererReady, rendererRef]);

    useEffect(() => {
        if (typeof window === 'undefined' || !rendererRef.current) return;
        const params = new URLSearchParams(window.location.search);
        if (params.get('shaderHotReload') !== '1') return;
        if (params.get('renderer') !== 'wasm') return;

        let cleanup: (() => void) | undefined;
        import('../dev/shaderHotReload').then(({ attachShaderHotReload, wrapLoadShaderForHotReload }) => {
            const manager = rendererRef.current!;
            const wrapped = wrapLoadShaderForHotReload(manager);
            (window as unknown as { __pixelocity__: Record<string, unknown> }).__pixelocity__ = {
                ...(window as unknown as { __pixelocity__: Record<string, unknown> }).__pixelocity__,
                loadShader: wrapped,
                reloadShader: (id: string, url: string) => manager.reloadShader(id, url),
            };
            cleanup = attachShaderHotReload(manager);
            console.log('[HotReload] Enabled — edit files in public/shaders/ to reload pipelines');
        });
        return () => cleanup?.();
    }, [rendererReady, rendererRef]);
}
