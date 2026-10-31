/**
 * ModMatrixPanel — sources × targets grid for the modulation bus (#1513 Part A).
 *
 * Rows are sources, columns are slot params (p1..p4 + compositor opacity) of every slot
 * holding a shader. A cell is a route; when on, it has depth / offset (in param units) and
 * a curve. Edits go straight to modulationStore, which forwards them to the render worker.
 * Lazy chunk: loaded by ModMatrixHost on first open.
 */
import React, { useEffect, useMemo, useState, useSyncExternalStore } from 'react';
import { modulationStore } from '../../modulation/store';
import type { ModCurve, ModSource, ModTarget, ModTargetParam, Route } from '../../modulation/types';
import { LFO_SHAPES, MOD_CURVES, SEQUENCER_STEPS } from '../../modulation/types';
import { hash01 } from '../../modulation/sources';
import type { ShaderEntry } from '../../renderer/types';

export interface ModMatrixPanelProps {
    modes: string[];
    availableModes: ShaderEntry[];
    initialTarget: ModTarget | null;
    onClose: () => void;
}

const PARAMS: ModTargetParam[] = ['p1', 'p2', 'p3', 'p4', 'opacity'];

export const SOURCE_PRESETS: Array<{ label: string; make: () => ModSource }> = [
    { label: 'LFO sine · 1 bar', make: () => ({ kind: 'lfo', shape: 'sine', unit: 'beats', rate: 4 }) },
    { label: 'LFO tri · 0.25 Hz', make: () => ({ kind: 'lfo', shape: 'tri', unit: 'hz', rate: 0.25 }) },
    { label: 'LFO S&H · 1 beat', make: () => ({ kind: 'lfo', shape: 'sh', unit: 'beats', rate: 1, seed: 1 }) },
    { label: 'Envelope · every beat', make: () => ({ kind: 'adsr', attack: 0.02, decay: 0.15, sustain: 0.4, release: 0.25, gate: { from: 'beat', every: 1, length: 0.5 } }) },
    { label: 'Envelope · onset', make: () => ({ kind: 'adsr', attack: 0.01, decay: 0.2, sustain: 0.3, release: 0.2, gate: { from: 'onset' } }) },
    { label: 'Audio bass', make: () => ({ kind: 'audio', band: 'bass' }) },
    { label: 'Audio mid', make: () => ({ kind: 'audio', band: 'mid' }) },
    { label: 'Audio high', make: () => ({ kind: 'audio', band: 'high' }) },
    { label: 'Audio onset', make: () => ({ kind: 'audio', band: 'onset' }) },
    {
        label: 'Sequencer · 16ths',
        make: () => ({ kind: 'sequencer', stepBeats: 0.25, steps: Array.from({ length: SEQUENCER_STEPS }, (_, i) => Math.round(hash01(7, i) * 100) / 100) }),
    },
    { label: 'Random walk', make: () => ({ kind: 'random', seed: 1, rate: 8, step: 0.08 }) },
    { label: 'External (MIDI CC 1)', make: () => ({ kind: 'external', key: 'midi-cc:ch1/cc1' }) },
];

export const sourceKey = (s: ModSource): string => JSON.stringify(s);

export function describeSource(s: ModSource): string {
    switch (s.kind) {
        case 'lfo': return `LFO ${s.shape} ${s.rate}${s.unit === 'hz' ? ' Hz' : ' beats'}`;
        case 'adsr': return `ADSR (${s.gate.from === 'beat' ? `every ${s.gate.every} beat` : s.gate.from === 'external' ? s.gate.key : 'onset'})`;
        case 'audio': return `Audio ${s.band}`;
        case 'sequencer': return `Seq 16 × ${s.stepBeats} beat`;
        case 'random': return `Random walk (seed ${s.seed})`;
        case 'external': return `Ext ${s.key}`;
    }
}

let routeCounter = 0;
const newRouteId = () => `mod-${Date.now().toString(36)}-${(routeCounter++).toString(36)}`;

function useRoutes(): readonly Route[] {
    return useSyncExternalStore(
        (cb) => modulationStore.subscribe(cb),
        () => modulationStore.getSnapshot().routes,
    );
}

const cellStyle: React.CSSProperties = { border: '1px solid #333', padding: '4px', verticalAlign: 'top', minWidth: '64px' };

function SourceEditor({ source, onChange }: { source: ModSource; onChange: (s: ModSource) => void }) {
    if (source.kind === 'lfo') {
        return (
            <span style={{ display: 'inline-flex', gap: '4px', marginLeft: '4px' }}>
                <select aria-label="LFO shape" value={source.shape} onChange={(e) => onChange({ ...source, shape: e.target.value as typeof source.shape })}>
                    {LFO_SHAPES.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
                <input aria-label="LFO rate" type="number" min={0.01} step={0.05} value={source.rate} style={{ width: '52px' }}
                    onChange={(e) => onChange({ ...source, rate: Math.max(0.01, parseFloat(e.target.value) || 0.01) })} />
                <select aria-label="LFO unit" value={source.unit} onChange={(e) => onChange({ ...source, unit: e.target.value as 'hz' | 'beats' })}>
                    <option value="hz">Hz</option>
                    <option value="beats">beats</option>
                </select>
            </span>
        );
    }
    if (source.kind === 'external') {
        return <input aria-label="External key" value={source.key} style={{ width: '120px', marginLeft: '4px' }} onChange={(e) => onChange({ ...source, key: e.target.value })} />;
    }
    if (source.kind === 'random') {
        return <input aria-label="Random seed" type="number" value={source.seed} style={{ width: '52px', marginLeft: '4px' }} onChange={(e) => onChange({ ...source, seed: parseInt(e.target.value, 10) || 0 })} />;
    }
    return null;
}

export function ModMatrixPanel({ modes, availableModes, initialTarget, onClose }: ModMatrixPanelProps) {
    const routes = useRoutes();
    const bpm = useSyncExternalStore((cb) => modulationStore.subscribe(cb), () => modulationStore.getBpm());
    const [extraRows, setExtraRows] = useState<ModSource[]>([]);
    const [preset, setPreset] = useState(0);

    useEffect(() => {
        const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [onClose]);

    const nameOf = useMemo(() => new Map(availableModes.map((m) => [m.id, m.name])), [availableModes]);
    const targets = useMemo(() => {
        const out: ModTarget[] = [];
        modes.forEach((id, slot) => {
            if (!id || id === 'none') return;
            for (const param of PARAMS) out.push({ slot, param });
        });
        // The pre-target is always a column, even before its slot reports a shader.
        if (initialTarget && !out.some((t) => t.slot === initialTarget.slot && t.param === initialTarget.param)) out.unshift(initialTarget);
        return out;
    }, [modes, initialTarget]);

    // Report every column's shader-definition range so depth / clamp use the real min/max.
    useEffect(() => {
        for (const t of targets) {
            if (t.param === 'opacity') continue;
            const id = modes[t.slot];
            const def = id ? availableModes.find((m) => m.id === id)?.params?.[Number(t.param.slice(1)) - 1] : undefined;
            if (def && Number.isFinite(def.min) && Number.isFinite(def.max)) modulationStore.setRange(t, { min: def.min, max: def.max });
        }
    }, [targets, modes, availableModes]);

    const rows = useMemo(() => {
        const seen = new Map<string, ModSource>();
        for (const r of routes) seen.set(sourceKey(r.source), r.source);
        for (const s of extraRows) if (!seen.has(sourceKey(s))) seen.set(sourceKey(s), s);
        return [...seen.values()];
    }, [routes, extraRows]);

    const routeAt = (row: ModSource, t: ModTarget) =>
        routes.find((r) => sourceKey(r.source) === sourceKey(row) && r.target.slot === t.slot && r.target.param === t.param);

    const toggle = (row: ModSource, t: ModTarget) => {
        const existing = routeAt(row, t);
        if (existing) { modulationStore.removeRoute(existing.id); return; }
        const range = modulationStore.getRange(t);
        modulationStore.upsertRoute({ id: newRouteId(), source: row, target: t, depth: (range.max - range.min) * 0.5, offset: 0, curve: 'linear' });
    };

    const update = (route: Route, patch: Partial<Route>) => modulationStore.upsertRoute({ ...route, ...patch });

    const editRow = (row: ModSource, next: ModSource) => {
        const key = sourceKey(row);
        setExtraRows((rs) => rs.map((s) => (sourceKey(s) === key ? next : s)));
        modulationStore.setRoutes(modulationStore.getRoutes().map((r) => (sourceKey(r.source) === key ? { ...r, source: next } : r)));
    };

    const removeRow = (row: ModSource) => {
        const key = sourceKey(row);
        setExtraRows((rs) => rs.filter((s) => sourceKey(s) !== key));
        modulationStore.setRoutes(modulationStore.getRoutes().filter((r) => sourceKey(r.source) !== key));
    };

    const label = (t: ModTarget) => {
        const id = modes[t.slot];
        const entry = id ? availableModes.find((m) => m.id === id) : undefined;
        const idx = t.param === 'opacity' ? -1 : Number(t.param.slice(1)) - 1;
        const pname = t.param === 'opacity' ? 'opacity' : entry?.params?.[idx]?.name ?? t.param;
        return { slot: `S${t.slot + 1} ${id ? nameOf.get(id) ?? id : ''}`, param: pname };
    };

    return (
        <div role="dialog" aria-label="Modulation matrix" className="glass-card"
            style={{ position: 'fixed', left: '50%', top: '8%', transform: 'translateX(-50%)', zIndex: 2000, maxWidth: 'min(96vw, 1100px)', maxHeight: '84vh', overflow: 'auto', padding: '12px', background: 'rgba(12,12,20,0.96)', color: '#ddd', fontSize: '11px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                <strong className="gold-section-header" style={{ margin: 0 }}>Modulation</strong>
                <label>BPM <input aria-label="BPM" type="number" min={20} max={300} value={bpm} style={{ width: '56px' }}
                    onChange={(e) => modulationStore.setBpm(parseFloat(e.target.value))} /></label>
                <select aria-label="Source preset" value={preset} onChange={(e) => setPreset(parseInt(e.target.value, 10))}>
                    {SOURCE_PRESETS.map((p, i) => <option key={p.label} value={i}>{p.label}</option>)}
                </select>
                <button type="button" className="gold-outline-btn" onClick={() => {
                    const make = SOURCE_PRESETS[preset]?.make;
                    if (make) setExtraRows((rs) => [...rs, make()]);
                }}>+ Source</button>
                <span style={{ flex: 1 }} />
                <button type="button" className="gold-outline-btn" onClick={() => { setExtraRows([]); modulationStore.clear(); }}>Clear</button>
                <button type="button" className="gold-outline-btn" aria-label="Close modulation matrix" onClick={onClose}>✕</button>
            </div>
            {targets.length === 0 ? (
                <div style={{ fontStyle: 'italic', color: '#a0a0b0' }}>Load an effect into a slot to modulate it.</div>
            ) : (
                <table style={{ borderCollapse: 'collapse' }}>
                    <thead>
                        <tr>
                            <th style={cellStyle}>Source \ Target</th>
                            {targets.map((t) => {
                                const l = label(t);
                                const focus = initialTarget && t.slot === initialTarget.slot && t.param === initialTarget.param;
                                return (
                                    <th key={`${t.slot}:${t.param}`} style={{ ...cellStyle, color: focus ? '#FFD700' : '#a0a0b0', fontWeight: focus ? 700 : 400 }}>
                                        <div>{l.slot}</div><div>{l.param}</div>
                                    </th>
                                );
                            })}
                        </tr>
                    </thead>
                    <tbody>
                        {rows.length === 0 && (
                            <tr><td style={cellStyle} colSpan={targets.length + 1}>Add a source with “+ Source”.</td></tr>
                        )}
                        {rows.map((row) => (
                            <tr key={sourceKey(row)}>
                                <th style={{ ...cellStyle, textAlign: 'left', whiteSpace: 'nowrap' }}>
                                    {describeSource(row)}
                                    <SourceEditor source={row} onChange={(next) => editRow(row, next)} />
                                    <button type="button" aria-label={`Remove ${describeSource(row)}`} style={{ marginLeft: '4px' }} onClick={() => removeRow(row)}>🗑</button>
                                </th>
                                {targets.map((t) => {
                                    const route = routeAt(row, t);
                                    const range = modulationStore.getRange(t);
                                    const span = Math.max(1e-6, range.max - range.min);
                                    const l = label(t);
                                    return (
                                        <td key={`${t.slot}:${t.param}`} style={{ ...cellStyle, background: route ? 'rgba(255,215,0,0.08)' : undefined }}>
                                            <input type="checkbox" aria-label={`${describeSource(row)} → ${l.slot} ${l.param}`} checked={!!route} onChange={() => toggle(row, t)} />
                                            {route && (
                                                <div style={{ display: 'grid', gap: '2px' }}>
                                                    <input type="range" aria-label="Depth" title={`depth ${route.depth.toFixed(2)}`} min={-span} max={span} step={span / 100} value={route.depth}
                                                        onChange={(e) => update(route, { depth: parseFloat(e.target.value) })} />
                                                    <input type="range" aria-label="Offset" title={`offset ${route.offset.toFixed(2)}`} min={-span} max={span} step={span / 100} value={route.offset}
                                                        onChange={(e) => update(route, { offset: parseFloat(e.target.value) })} />
                                                    <select aria-label="Curve" value={route.curve} onChange={(e) => update(route, { curve: e.target.value as ModCurve })}>
                                                        {MOD_CURVES.map((c) => <option key={c} value={c}>{c}</option>)}
                                                    </select>
                                                </div>
                                            )}
                                        </td>
                                    );
                                })}
                            </tr>
                        ))}
                    </tbody>
                </table>
            )}
            <div style={{ marginTop: '6px', color: '#80808f' }}>
                value = clamp(base + depth × curve(source) + offset, min, max). Opacity applies to slots in a blend layer.
            </div>
        </div>
    );
}

export default ModMatrixPanel;
