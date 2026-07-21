import { useEffect, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';
import { RenderQualityMode } from '../config/performancePolicy';

export interface CanvasImageStats {
    width: number;
    height: number;
    meanLuminance: number;
    activePixelRatio: number;
}

function measureCanvasStats(canvas: HTMLCanvasElement): CanvasImageStats {
    const w = canvas.width;
    const h = canvas.height;
    const tmp = document.createElement('canvas');
    tmp.width = w;
    tmp.height = h;
    const ctx = tmp.getContext('2d');
    if (!ctx) {
        return { width: w, height: h, meanLuminance: 0, activePixelRatio: 0 };
    }
    ctx.drawImage(canvas, 0, 0);
    const { data } = ctx.getImageData(0, 0, w, h);
    let lumSum = 0;
    let active = 0;
    const pixels = w * h;
    for (let i = 0; i < data.length; i += 4) {
        const r = data[i] / 255;
        const g = data[i + 1] / 255;
        const b = data[i + 2] / 255;
        const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        lumSum += lum;
        if (lum > 0.05) active++;
    }
    return {
        width: w,
        height: h,
        meanLuminance: lumSum / pixels,
        activePixelRatio: active / pixels,
    };
}

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
                captureCanvasStats: (): CanvasImageStats => {
                    const canvas = document.querySelector('canvas');
                    if (!canvas) return { width: 0, height: 0, meanLuminance: 0, activePixelRatio: 0 };
                    return measureCanvasStats(canvas);
                },
                captureThumbnailPng: async (outSize = 256): Promise<string | null> => {
                    const canvas = document.querySelector('canvas');
                    if (!canvas) return null;
                    const tmp = document.createElement('canvas');
                    tmp.width = outSize;
                    tmp.height = outSize;
                    const ctx = tmp.getContext('2d');
                    if (!ctx) return null;
                    ctx.drawImage(canvas, 0, 0, outSize, outSize);
                    const dataUrl = tmp.toDataURL('image/png');
                    return dataUrl.replace(/^data:image\/png;base64,/, '');
                },
                waitFrames: (frameCount: number): Promise<void> =>
                    new Promise((resolve) => {
                        let count = 0;
                        const tick = () => {
                            count += 1;
                            if (count >= frameCount) resolve();
                            else requestAnimationFrame(tick);
                        };
                        requestAnimationFrame(tick);
                    }),
                setRenderQuality: (mode: RenderQualityMode) => {
                    manager.setRenderQuality(mode, {
                        supportsDeepWorkgroup: manager.getSupportsDeepWorkgroup(),
                    });
                },
                loadImage: (url: string) => manager.loadImage(url),
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
                getAdapterSummary: () => {
                    const diags = manager.getDiagnostics();
                    return diags.wasm?.adapterInfo ?? '';
                },
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
