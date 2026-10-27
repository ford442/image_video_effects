import React from 'react';
import type { SlotMode } from '../../../renderer/types';
import {
    BLEND_MODES,
    LAYER_CHOICE_LABELS,
    applyLayerChoice,
    layerChoice,
    type LayerChoice,
    type LayerMask,
    type SlotLayer,
} from '../../../renderer/layerState';

/**
 * Layer strip row (#1512): one line under a slot chip with chained/parallel,
 * blend mode, opacity and mask source. Feather and key threshold are set
 * through the API, chain links and project files.
 */
export interface SlotLayerRowProps {
    slotIndex: number;
    slotCount: number;
    mode: SlotMode;
    layer: SlotLayer;
    onModeChange: (mode: SlotMode) => void;
    onLayerChange: (layer: SlotLayer) => void;
    /** False on WASM / Canvas2D, which always composite as replace. */
    available?: boolean;
}

const CHOICES: LayerChoice[] = ['replace', ...BLEND_MODES, 'mask'];

/** Mask picker value: none, l, !l, d, !d, s<N>, !s<N> (the chain-link mask ref without feather). */
function maskValue(mask: LayerMask): string {
    if (mask.source === 'none') return 'none';
    const src = mask.source === 'luma' ? 'l' : mask.source === 'depth' ? 'd' : `s${mask.slot ?? 0}`;
    return `${mask.invert ? '!' : ''}${src}`;
}

function maskFromValue(value: string, previous: LayerMask): LayerMask {
    if (value === 'none') return { source: 'none' };
    const invert = value.startsWith('!');
    const src = invert ? value.slice(1) : value;
    const feather = previous.feather ? { feather: previous.feather } : {};
    if (src === 'l') return { source: 'luma', ...(invert ? { invert } : {}), ...feather };
    if (src === 'd') return { source: 'depth', ...(invert ? { invert } : {}), ...feather };
    return { source: 'slot', slot: Number(src.slice(1)), ...(invert ? { invert } : {}), ...feather };
}

const rowStyle: React.CSSProperties = {
    display: 'flex',
    gap: '4px',
    alignItems: 'center',
    marginTop: '6px',
    fontSize: '11px',
};

const selectStyle: React.CSSProperties = { flex: '1 1 0', minWidth: 0, padding: '2px 4px', fontSize: '11px' };

export const SlotLayerRow: React.FC<SlotLayerRowProps> = ({
    slotIndex,
    slotCount,
    mode,
    layer,
    onModeChange,
    onLayerChange,
    available = true,
}) => {
    const blending = layer.output === 'blend';
    const label = `Slot ${slotIndex + 1}`;
    const stop = (e: React.SyntheticEvent) => e.stopPropagation();
    return (
        <div style={rowStyle} onClick={stop} data-testid={`slot-layer-row-${slotIndex}`}>
            <button
                type="button"
                className="gold-badge"
                aria-label={`${label} execution: ${mode}`}
                title={mode === 'parallel'
                    ? 'Parallel: reads the same input as the other parallel slots; they composite together'
                    : 'Chained: reads the previous slot\'s output'}
                onClick={() => onModeChange(mode === 'parallel' ? 'chained' : 'parallel')}
                style={{ cursor: 'pointer', padding: '2px 6px', fontSize: '11px' }}
            >
                {mode === 'parallel' ? '⚡' : '⛓️'}
            </button>
            <select
                className="glass-select"
                aria-label={`${label} blend mode`}
                title={available ? 'How this slot joins the image below it' : 'Compositing needs the TypeScript WebGPU renderer'}
                disabled={!available}
                value={layerChoice(layer)}
                onChange={(e) => onLayerChange(applyLayerChoice(layer, e.target.value as LayerChoice))}
                style={selectStyle}
            >
                {CHOICES.map((choice) => (
                    <option key={choice} value={choice}>{LAYER_CHOICE_LABELS[choice]}</option>
                ))}
            </select>
            <input
                type="range"
                className="glass-range"
                aria-label={`${label} opacity`}
                title={`Opacity ${Math.round(layer.opacity * 100)}% (MIDI / OSC param "opacity")`}
                min={0}
                max={1}
                step={0.01}
                disabled={!available || !blending}
                value={layer.opacity}
                onChange={(e) => onLayerChange({ ...layer, opacity: Number(e.target.value) })}
                style={{ flex: '1 1 0', minWidth: 0 }}
            />
            <select
                className="glass-select"
                aria-label={`${label} mask`}
                title="Mask: where this layer shows"
                disabled={!available || !blending}
                value={maskValue(layer.mask)}
                onChange={(e) => onLayerChange({ ...layer, mask: maskFromValue(e.target.value, layer.mask) })}
                style={selectStyle}
            >
                <option value="none">No mask</option>
                <option value="l">Luma</option>
                <option value="!l">Luma (inv)</option>
                <option value="d">Depth</option>
                <option value="!d">Depth (inv)</option>
                {Array.from({ length: slotCount }, (_, i) => i)
                    .filter((i) => i !== slotIndex)
                    .flatMap((i) => [
                        <option key={`s${i}`} value={`s${i}`}>Slot {i + 1}</option>,
                        <option key={`!s${i}`} value={`!s${i}`}>Slot {i + 1} (inv)</option>,
                    ])}
            </select>
        </div>
    );
};

export default SlotLayerRow;
