import { useEffect, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';
import { RenderQualityMode } from '../config/performancePolicy';
import { computeBenchmarkStats, countReadbacks } from '../utils/benchmarkStats';

export interface CanvasImageStats {
    width: number;
    height: number;
    meanLuminance: number;
    activePixelRatio: number;
}

/** Draw a captured frame (data URL) into a canvas so it can be measured. */
async function canvasFromDataUrl(dataUrl: string): Promise<HTMLCanvasElement | null> {
    if (!dataUrl) return null;
    const img = new Image();
    img.src = dataUrl;
    await img.decode();
    const canvas = document.createElement('canvas');
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    canvas.getContext('2d')?.drawImage(img, 0, 0);
    return canvas;
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
        const r = data[i]! / 255;
        const g = data[i + 1]! / 255;
        const b = data[i + 2]! / 255;
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
            const loadShaderTracked = async (
                id: string,
                url: string,
                meta?: Parameters<typeof manager.loadShader>[2],
            ) => {
                const ok = await manager.loadShader(id, url, meta) ?? false;
                if (params.get('shaderHotReload') === '1') {
                    import('../dev/shaderHotReload').then(({ trackShaderForHotReload }) => {
                        trackShaderForHotReload(id, url);
                    }).catch((err) => console.warn('[HotReload] Failed to load module:', err));
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
                // A render-worker canvas cannot be read on the page (#1314): capture over RPC.
                captureCanvasScreenshot: async () => {
                    if (manager.getRenderThread() === 'worker') return (await manager.refreshFrameImage()) || null;
                    const canvas = document.querySelector('canvas');
                    if (!canvas) return null;
                    return canvas.toDataURL('image/png');
                },
                captureCanvasStats: async (): Promise<CanvasImageStats> => {
                    const canvas = manager.getRenderThread() === 'worker'
                        ? await canvasFromDataUrl(await manager.refreshFrameImage())
                        : document.querySelector('canvas');
                    if (!canvas) return { width: 0, height: 0, meanLuminance: 0, activePixelRatio: 0 };
                    return measureCanvasStats(canvas);
                },
                captureThumbnailPng: async (outSize = 256): Promise<string | null> => {
                    const chores = await manager.captureThumbnailPng?.(outSize);
                    if (chores) return chores;
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
                /** Lift the quality slot cap so multi-slot stacks run on low-end/SwiftShader adapters. */
                overrideSlotCap: (cap: number | null) => manager.overrideSlotCapForTests(cap),
                setRenderQuality: (mode: RenderQualityMode) => {
                    manager.setRenderQuality(mode, {
                        supportsDeepWorkgroup: manager.getSupportsDeepWorkgroup(),
                        formatCaps: manager.getFormatCapabilities(),
                    });
                },
                loadImage: (url: string) => manager.loadImage(url),
                runBenchmark: async (
                    frameCount = 90,
                    options?: { qualityMode?: RenderQualityMode; warmupFrames?: number },
                ) => {
                    if (options?.qualityMode) {
                        manager.setRenderQuality(options.qualityMode, {
                            supportsDeepWorkgroup: manager.getSupportsDeepWorkgroup(),
                            formatCaps: manager.getFormatCapabilities(),
                        });
                    }
                    const perf = manager.getPerformanceStatus();
                    // Discarded warm-up frames (#1357 T5): pipelines settle before sampling.
                    const warmupFrames = Math.max(0, options?.warmupFrames ?? 10);
                    for (let i = 0; i < warmupFrames; i++) {
                        await new Promise<void>((r) => requestAnimationFrame(() => r()));
                    }
                    const samples: Array<{ fps: number; gpu: ReturnType<typeof manager.getGPUTimings> }> = [];
                    for (let i = 0; i < frameCount; i++) {
                        await new Promise<void>((r) => requestAnimationFrame(() => r()));
                        samples.push({
                            fps: manager.getMetrics().fps,
                            gpu: manager.getGPUTimings(),
                        });
                    }
                    const totals = samples.map((s) => s.gpu.totalTime).filter((t) => t > 0);
                    const status = manager.getPerformanceStatus();
                    const avgTotalMs = totals.length
                        ? totals.reduce((a, b) => a + b, 0) / totals.length
                        : 0;
                    return {
                        frames: frameCount,
                        avgFps: samples.reduce((a, s) => a + s.fps, 0) / frameCount,
                        avgTotalMs,
                        gpuTimingsAvailable: samples.some((s) => s.gpu.available),
                        rendererType: manager.getActiveRendererType(),
                        qualityMode: options?.qualityMode ?? perf.qualityMode,
                        colorFormat: status.colorFormat,
                        estimatedTextureMiB: status.estimatedTextureMiB,
                        // Format-tier bench fields (docs/FORMAT_TIERS.md — Benchmarking).
                        requestedColorFormat: status.requestedColorFormat,
                        fp32Pinned: status.fp32Pinned,
                        fp32PinnedBy: status.fp32PinnedBy,
                        maxPassesPerFrame: status.maxPassesPerFrame,
                        internalWidth: status.internalWidth,
                        internalHeight: status.internalHeight,
                        scale: status.scale,
                        // Timestamp-honesty gate: 'gpu-timestamp' only after a real readback.
                        timingSource: samples[samples.length - 1]?.gpu.timingSource ?? 'wall-clock',
                        hasRealGpuTimings: samples.some((s) => s.gpu.timingSource === 'gpu-timestamp'),
                        // Per-pass GPU ms (#1314 WP-4): per-shader evidence, not just per frame.
                        passTimings: manager.getPassTimings(),
                        // Stats over every sampled frame (#1357 T4); `samples` is only the tail.
                        warmupFrames,
                        totalMsStats: computeBenchmarkStats(totals),
                        // TS reads timestamps back every 250 ms, so many frames repeat a value:
                        // distinct values are the real GPU sample size (#1080).
                        gpuReadbacks: countReadbacks(samples.map((s) => s.gpu.totalTime)),
                        fpsStats: computeBenchmarkStats(samples.map((s) => s.fps)),
                        timestampPeriodNs: manager.getDiagnostics().webgpu?.timing?.periodNs ?? 0,
                        samples: samples.slice(-5),
                    };
                },
                /**
                 * Vsync-free ms/frame (#1080): the backend pauses its loop, renders
                 * `frameCount` frames back to back and times to GPU idle.
                 */
                runUncappedBenchmark: async (frameCount = 120, warmupFrames = 10) => {
                    if (warmupFrames > 0) await manager.benchmarkUncapped(warmupFrames);
                    const result = await manager.benchmarkUncapped(frameCount);
                    return result ? {
                        ...result,
                        rendererType: manager.getActiveRendererType(),
                        renderThread: manager.getRenderThread(),
                    } : null;
                },
                updateAudioFrequencyBins: (bins: Float32Array) => {
                    manager.updateAudioFrequencyBins(bins);
                },
                getSlotState: (index: number) => manager.getSlotState(index),
                getPerformanceStatus: () => manager.getPerformanceStatus(),
                releaseFp32Requirement: (id: string) => manager.releaseFp32Requirement(id),
                getGPUTimings: () => manager.getGPUTimings(),
                getPassTimings: () => manager.getPassTimings(),
                getRenderThread: () => manager.getRenderThread(),
                /** Destroy the TS WebGPU device but report it as a runtime loss (main + worker). */
                simulateDeviceLoss: () => manager.simulateDeviceLoss(),
                /** Worker mode only: an uncaught error in the render worker (#1395). */
                simulateWorkerCrash: () => manager.simulateWorkerCrash(),
                getDeviceRecoveryStatus: () => manager.getDeviceRecoveryStatus(),
                recoverFromDeviceLoss: () => manager.recoverFromDeviceLoss(),
                /**
                 * Record `ms` through the app's WebCodecs session (worker frame grabs in
                 * worker mode, canvas VideoFrames on the page) and describe the WebM.
                 */
                recordClip: async (ms = 1500, size = 512, fps = 10) => {
                    const { startGpuEncodeSession } = await import('../recording/gpuEncodeSupport');
                    const canvas = document.querySelector('canvas[data-testid="webgpu-canvas"]') as HTMLCanvasElement | null;
                    if (!canvas) return null;
                    const session = await startGpuEncodeSession({
                        canvas,
                        supportsCanvasCopySrc: () => manager.supportsCanvasFrameCapture(),
                        setCanvasCopySrc: (enabled) => manager.setCanvasCopySrc(enabled),
                        readback: null,
                        grabFrame: manager.getWorkerFrameGrabber(),
                    }, { width: size, height: size, fps, bitrate: 2_000_000 });
                    if (!session) return null;
                    await new Promise((r) => setTimeout(r, ms));
                    // A worker grab waits for the next presented frame; on a slow
                    // device (SwiftShader, ~1 fps at 1024²) none may land within `ms`.
                    const deadline = performance.now() + 15_000;
                    while (session.framesEncoded === 0 && performance.now() < deadline) {
                        await new Promise((r) => setTimeout(r, 100));
                    }
                    const frames = session.framesEncoded;
                    const blob = await session.stop();
                    return { kind: session.kind, size: blob.size, type: blob.type, frames };
                },
                setNodeScale: (slot: number, nodeId: string, scale: number) =>
                    manager.setNodeScale(slot, nodeId, scale),
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
        }).catch((err) => console.warn('[HotReload] Failed to load module:', err));
        return () => cleanup?.();
    }, [rendererReady, rendererRef]);
}
