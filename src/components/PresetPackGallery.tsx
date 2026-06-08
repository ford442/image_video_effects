/**
 * PresetPackGallery.tsx
 *
 * Curated gallery of hand-built multi-slot shader chains ("preset packs").
 * Each pack restores in a single click via the same SharedChain apply path
 * used by share-link hydration.
 */

import React, { useEffect, useRef, useState } from 'react';
import { SharedChain } from '../services/layerChainShare';

export interface PresetPack {
    id: string;
    name: string;
    description: string;
    chain: SharedChain;
}

interface PresetPackFile {
    version: number;
    packs: PresetPack[];
}

export interface PresetPackGalleryProps {
    open: boolean;
    onToggle: () => void;
    onApplyPack: (chain: SharedChain) => void;
}

export const PresetPackGallery: React.FC<PresetPackGalleryProps> = ({ open, onToggle, onApplyPack }) => {
    const [packs, setPacks] = useState<PresetPack[]>([]);
    const [status, setStatus] = useState<'idle' | 'loading' | 'loaded' | 'error'>('idle');
    const fetchStartedRef = useRef(false);

    useEffect(() => {
        if (!open || fetchStartedRef.current) return;
        fetchStartedRef.current = true;

        let cancelled = false;
        setStatus('loading');

        fetch('/preset_packs.json')
            .then(res => {
                if (!res.ok) throw new Error(`HTTP ${res.status}`);
                return res.json();
            })
            .then((data: PresetPackFile) => {
                if (cancelled) return;
                setPacks(Array.isArray(data?.packs) ? data.packs : []);
                setStatus('loaded');
            })
            .catch(err => {
                if (cancelled) return;
                console.warn('[PresetPackGallery] failed to load preset packs:', err);
                setStatus('error');
            });

        return () => { cancelled = true; };
    }, [open]);

    return (
        <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
            <div
                className="gold-section-header"
                style={{ fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }}
                onClick={onToggle}
            >
                <span>Preset Packs</span>
                <span style={{ transform: open ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>▼</span>
            </div>
            {open && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '300px', overflowY: 'auto', marginTop: '8px' }}>
                    {status === 'loading' && (
                        <div style={{ fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center' }}>
                            Loading packs…
                        </div>
                    )}
                    {status === 'error' && (
                        <div style={{ fontSize: '12px', color: '#ff8080', fontStyle: 'italic', textAlign: 'center' }}>
                            Couldn't load preset packs.
                        </div>
                    )}
                    {status === 'loaded' && packs.length === 0 && (
                        <div style={{ fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center' }}>
                            No preset packs available
                        </div>
                    )}
                    {packs.map(pack => {
                        const idDisplay = pack.chain.slots
                            .filter(s => s.shaderId)
                            .map(s => s.shaderId)
                            .slice(0, 3)
                            .join(', ');
                        return (
                            <div key={pack.id} style={{
                                background: 'rgba(20, 20, 30, 0.6)',
                                border: '1px solid rgba(255, 215, 0, 0.1)',
                                borderRadius: '6px',
                                padding: '8px',
                            }}>
                                <div style={{ fontSize: '12px', color: '#FFD700', fontWeight: 500, marginBottom: '4px' }}>
                                    {pack.name}
                                </div>
                                <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)', marginBottom: '6px' }}>
                                    {pack.description}
                                </div>
                                <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.4)', marginBottom: '6px', fontStyle: 'italic' }}>
                                    {idDisplay}
                                </div>
                                <button
                                    className="gold-outline-btn"
                                    style={{ fontSize: '11px', padding: '3px 8px', width: '100%' }}
                                    onClick={() => onApplyPack(pack.chain)}
                                >
                                    Load Pack
                                </button>
                            </div>
                        );
                    })}
                </div>
            )}
        </div>
    );
};

export default PresetPackGallery;
