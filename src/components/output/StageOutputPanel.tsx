/**
 * StageOutputPanel — open stage windows and corner-pin them (docs/STAGE_OUTPUTS.md).
 *
 * Lazy chunk (StageOutputHost). Creates the control window's StageController on
 * first open and hooks it to RendererManager.onBackendReady, so stages re-attach
 * after a backend switch or device-loss recovery. Closing the panel leaves the
 * stages running.
 */
import React, { RefObject, useCallback, useEffect, useRef, useState } from 'react';
import type { RendererManager } from '../../renderer/RendererManager';
import { DEFAULT_OUTPUT_COLOUR, defaultOutputConfig, setCorner, TEST_PATTERNS, type OutputConfig, type TestPattern } from '../../output/outputConfig';
import { isConvexQuad } from '../../output/homography';
import {
    getStageController,
    listScreens,
    type ScreenPlacement,
    type StageController,
    type StageInfo,
} from '../../output/stageController';

export interface StageOutputPanelProps {
    rendererRef: RefObject<RendererManager | null>;
    onClose: () => void;
}

let unhookBackendReady: (() => void) | null = null;
let hookedManager: RendererManager | null = null;

/** The controller, wired to the current manager's backend (once per manager). */
export function controllerFor(rendererRef: RefObject<RendererManager | null>): StageController {
    const controller = getStageController(() => ({
        win: window,
        getBackend: () => rendererRef.current?.getOutputBackend() ?? null,
    }));
    const manager = rendererRef.current;
    if (manager && manager !== hookedManager) {
        unhookBackendReady?.();
        unhookBackendReady = manager.onBackendReady(() => controller.reattachAll());
        hookedManager = manager;
    }
    return controller;
}

const CORNER_NAMES = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];
const STATE_COLOURS: Record<StageInfo['state'], string> = {
    opening: '#aaa',
    attaching: '#e0b84a',
    live: '#5fd38a',
    failed: '#ff6b6b',
    closed: '#777',
};

function CornerEditor({ stage, controller }: { stage: StageInfo; controller: StageController }) {
    const ref = useRef<SVGSVGElement | null>(null);
    const [drag, setDrag] = useState<number | null>(null);
    const aspect = stage.height > 0 ? stage.width / stage.height : 16 / 9;
    const w = 320;
    const h = Math.max(60, Math.min(320, Math.round(w / aspect)));
    // The editor shows the output with a margin, so off-screen corners stay reachable.
    const margin = 0.15;
    const toView = (x: number, y: number) => [((x + margin) / (1 + 2 * margin)) * w, ((y + margin) / (1 + 2 * margin)) * h] as const;
    const fromEvent = (e: React.PointerEvent) => {
        const rect = ref.current?.getBoundingClientRect();
        if (!rect || rect.width === 0 || rect.height === 0) return null;
        const vx = (e.clientX - rect.left) / rect.width;
        const vy = (e.clientY - rect.top) / rect.height;
        return [vx * (1 + 2 * margin) - margin, vy * (1 + 2 * margin) - margin] as const;
    };
    const corners = stage.config.corners;
    const points = corners.map((c) => toView(c[0], c[1]).join(',')).join(' ');
    const [ox0, oy0] = toView(0, 0);
    const [ox1, oy1] = toView(1, 1);
    const convex = isConvexQuad(corners);

    const onPointerMove = (e: React.PointerEvent) => {
        if (drag === null) return;
        const p = fromEvent(e);
        if (p) controller.setConfig(stage.id, setCorner(stage.config, drag, p[0], p[1]));
    };

    return (
        <svg
            ref={ref}
            width={w}
            height={h}
            tabIndex={0}
            role="application"
            aria-label={`Corner pin for ${stage.id}: 1–4 or Tab select a corner, arrows move it (Shift ×10)`}
            style={{ background: '#05050a', border: '1px solid #333', borderRadius: 4, touchAction: 'none', outline: 'none' }}
            onKeyDown={(e) => {
                if (controller.handleKey(stage.id, e.key, { shift: e.shiftKey, alt: e.altKey })) e.preventDefault();
            }}
            onPointerMove={onPointerMove}
            onPointerUp={() => setDrag(null)}
            onPointerCancel={() => setDrag(null)}
        >
            <rect x={ox0} y={oy0} width={ox1 - ox0} height={oy1 - oy0} fill="#111" stroke="#555" strokeDasharray="4 3" />
            <polygon points={points} fill={convex ? 'rgba(80,160,255,0.18)' : 'rgba(255,80,80,0.25)'} stroke={convex ? '#5aa0ff' : '#ff6b6b'} />
            {corners.map((c, i) => {
                const [x, y] = toView(c[0], c[1]);
                const selected = i === stage.selected;
                return (
                    <circle
                        key={CORNER_NAMES[i]}
                        cx={x}
                        cy={y}
                        r={selected ? 8 : 6}
                        fill={selected ? '#ffb347' : '#ddd'}
                        stroke="#000"
                        style={{ cursor: 'grab' }}
                        aria-label={CORNER_NAMES[i]}
                        onPointerDown={(e) => {
                            (e.target as Element).setPointerCapture?.(e.pointerId);
                            controller.selectCorner(stage.id, i);
                            setDrag(i);
                        }}
                    />
                );
            })}
        </svg>
    );
}

function Slider({ label, value, min, max, step, onChange }: { label: string; value: number; min: number; max: number; step: number; onChange: (v: number) => void }) {
    return (
        <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: 70 }}>{label}</span>
            <input type="range" aria-label={label} min={min} max={max} step={step} value={value} onChange={(e) => onChange(parseFloat(e.target.value))} />
            <span style={{ width: 36, textAlign: 'right' }}>{value.toFixed(2)}</span>
        </label>
    );
}

function StageCard({ stage, controller }: { stage: StageInfo; controller: StageController }) {
    const [name, setName] = useState('');
    const [named, setNamed] = useState<string[]>(() => controller.calibrations.listNamed());
    const status = controller.status(stage.id);
    const patch = (fn: (c: OutputConfig) => OutputConfig) => controller.updateConfig(stage.id, fn);

    return (
        <div style={{ border: '1px solid #2a2a38', borderRadius: 6, padding: 8, marginTop: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                <strong>{stage.id}</strong>
                <span style={{ color: STATE_COLOURS[stage.state] }}>● {stage.state}</span>
                <span style={{ color: '#888' }}>{stage.width}×{stage.height}{stage.screenLabel ? ` · ${stage.screenLabel}` : ''}</span>
                {status ? <span style={{ color: '#888' }}>{status.framesPresented} frames</span> : null}
                <span style={{ flex: 1 }} />
                {stage.state !== 'closed' ? (
                    <>
                        <button onClick={() => controller.identify(stage.id)}>Identify</button>
                        <button onClick={() => controller.close(stage.id)}>Close</button>
                    </>
                ) : (
                    <>
                        <button onClick={() => controller.open({ id: stage.id })}>Reopen</button>
                        <button onClick={() => controller.remove(stage.id)}>Remove</button>
                    </>
                )}
            </div>
            {stage.error ? <div role="alert" style={{ color: '#ff8a8a', marginBottom: 6 }}>{stage.error}</div> : null}
            {status?.singular ? <div style={{ color: '#ff8a8a' }}>These corners are degenerate — showing the unwarped picture.</div> : null}
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
                <CornerEditor stage={stage} controller={controller} />
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 220 }}>
                    <label>
                        Test pattern{' '}
                        <select aria-label="Test pattern" value={stage.config.testPattern}
                            onChange={(e) => patch((c) => ({ ...c, testPattern: e.target.value as TestPattern }))}>
                            {TEST_PATTERNS.map((p) => <option key={p} value={p}>{p}</option>)}
                        </select>
                    </label>
                    <label>
                        <input type="checkbox" checked={stage.config.outline} onChange={(e) => patch((c) => ({ ...c, outline: e.target.checked }))} /> Outline
                    </label>
                    <Slider label="Gain" value={stage.config.colour.gain} min={0} max={2} step={0.01}
                        onChange={(v) => patch((c) => ({ ...c, colour: { ...c.colour, gain: v } }))} />
                    <Slider label="Gamma" value={stage.config.colour.gamma} min={0.5} max={2} step={0.01}
                        onChange={(v) => patch((c) => ({ ...c, colour: { ...c.colour, gamma: v } }))} />
                    <Slider label="Black level" value={stage.config.colour.blackLevel} min={0} max={0.2} step={0.005}
                        onChange={(v) => patch((c) => ({ ...c, colour: { ...c.colour, blackLevel: v } }))} />
                    <div style={{ display: 'flex', gap: 6 }}>
                        <button onClick={() => patch((c) => ({ ...c, corners: defaultOutputConfig().corners }))}>Reset corners</button>
                        <button onClick={() => patch((c) => ({ ...c, colour: { ...DEFAULT_OUTPUT_COLOUR } }))}>Reset colour</button>
                    </div>
                    <div style={{ display: 'flex', gap: 6 }}>
                        <input aria-label="Calibration name" placeholder="Calibration name" value={name} style={{ width: 120 }}
                            onChange={(e) => setName(e.target.value)} />
                        <button disabled={!name.trim()} onClick={() => {
                            if (controller.calibrations.saveNamed(name, stage.config)) {
                                setNamed(controller.calibrations.listNamed());
                                setName('');
                            }
                        }}>Save</button>
                    </div>
                    {named.length > 0 ? (
                        <div style={{ display: 'flex', gap: 6 }}>
                            <select aria-label="Load calibration" defaultValue="" onChange={(e) => {
                                const cfg = e.target.value ? controller.calibrations.loadNamed(e.target.value) : null;
                                if (cfg) controller.setConfig(stage.id, cfg);
                                e.target.value = '';
                            }}>
                                <option value="">Load calibration…</option>
                                {named.map((n) => <option key={n} value={n}>{n}</option>)}
                            </select>
                            <select aria-label="Delete calibration" defaultValue="" onChange={(e) => {
                                if (e.target.value) controller.calibrations.deleteNamed(e.target.value);
                                setNamed(controller.calibrations.listNamed());
                                e.target.value = '';
                            }}>
                                <option value="">Delete…</option>
                                {named.map((n) => <option key={n} value={n}>{n}</option>)}
                            </select>
                        </div>
                    ) : null}
                </div>
            </div>
        </div>
    );
}

export function StageOutputPanel({ rendererRef, onClose }: StageOutputPanelProps) {
    const [controller] = useState(() => controllerFor(rendererRef));
    const [stages, setStages] = useState<StageInfo[]>(() => controller.list());
    const [screens, setScreens] = useState<ScreenPlacement[] | null | undefined>(undefined);
    const [screenIndex, setScreenIndex] = useState(-1);
    const [, setTick] = useState(0);

    useEffect(() => controller.subscribe(setStages), [controller]);
    // Frame counters come from the renderer snapshot; refresh them while the panel is open.
    useEffect(() => {
        const t = setInterval(() => setTick((n) => n + 1), 1000);
        return () => clearInterval(t);
    }, []);
    useEffect(() => {
        const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [onClose]);

    const findScreens = useCallback(async () => {
        const list = await listScreens(window);
        setScreens(list);
        const external = list?.findIndex((s) => !s.isPrimary) ?? -1;
        setScreenIndex(external);
    }, []);

    const noBackend = !rendererRef.current?.getOutputBackend();

    return (
        <div role="dialog" aria-label="Stage outputs" className="glass-card"
            style={{ position: 'fixed', right: '2%', top: '8%', zIndex: 2000, width: 'min(96vw, 640px)', maxHeight: '84vh', overflow: 'auto', padding: 12, background: 'rgba(12,12,20,0.96)', color: '#ddd', fontSize: 11 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <strong className="gold-section-header" style={{ margin: 0 }}>Stage outputs</strong>
                <span style={{ flex: 1 }} />
                <button aria-label="Close stage outputs" onClick={onClose}>✕</button>
            </div>
            <p style={{ color: '#999', margin: '6px 0' }}>
                A stage is a separate window that shows the program full-screen on a projector or LED wall, rendered by the
                same GPU device. Drag the corners to fit the picture to the surface.
            </p>
            {noBackend ? (
                <div role="alert" style={{ color: '#ff8a8a' }}>Stage outputs need the WebGPU renderer (not WASM / Canvas2D).</div>
            ) : null}
            <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                <button onClick={() => void findScreens()}>Find displays</button>
                {screens ? (
                    <select aria-label="Display" value={screenIndex} onChange={(e) => setScreenIndex(parseInt(e.target.value, 10))}>
                        <option value={-1}>Any (move it yourself)</option>
                        {screens.map((s, i) => (
                            <option key={`${s.label}-${i}`} value={i}>{s.label} {s.width}×{s.height}{s.isPrimary ? ' (primary)' : ''}</option>
                        ))}
                    </select>
                ) : null}
                <button disabled={noBackend} onClick={() => controller.open({ screen: screens?.[screenIndex] ?? null })}>Open stage window</button>
            </div>
            {screens === null ? (
                <p style={{ color: '#999' }}>
                    Display placement is unavailable here (the Window Management API is Chromium-only and needs permission).
                    Open the stage, drag it to the projector and press F there.
                </p>
            ) : null}
            <p style={{ color: '#777', margin: '6px 0 0' }}>
                In a stage window: F or double-click toggles fullscreen · 1–4 / Tab select a corner · arrows nudge (Shift ×10) · T test pattern · O outline.
            </p>
            {stages.map((s) => <StageCard key={s.id} stage={s} controller={controller} />)}
        </div>
    );
}

export default StageOutputPanel;
