import React, { useState } from 'react';
import type { UseOscControlReturn } from '../hooks/useOscControl';

const STATUS_LABEL: Record<UseOscControlReturn['oscStatus'], string> = {
    off: 'Off',
    connecting: 'Connecting…',
    open: 'Connected',
    closed: 'Disconnected — retrying',
    error: 'Relay unreachable',
};

/** OSC bridge toggle + relay URL. Shown on mobile too (WebSocket, not WebMIDI). */
export const OscPanel: React.FC<{ osc: UseOscControlReturn }> = ({ osc }) => {
    const [draftUrl, setDraftUrl] = useState(osc.oscUrl);
    const statusColor = osc.oscStatus === 'open' ? '#7CFC9A' : osc.oscStatus === 'off' ? '#a0a0b0' : '#FFB347';

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px', fontSize: '12px' }}>
            <label style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <span>Enable OSC bridge</span>
                <input type="checkbox" checked={osc.oscEnabled} onChange={(e) => osc.setOscEnabled(e.target.checked)} />
            </label>
            <div style={{ display: 'flex', gap: '6px' }}>
                <input
                    type="text"
                    className="glass-input"
                    aria-label="OSC relay WebSocket URL"
                    value={draftUrl}
                    onChange={(e) => setDraftUrl(e.target.value)}
                    style={{ flex: 1, fontSize: '11px' }}
                />
                <button
                    type="button"
                    className="gold-outline-btn"
                    style={{ fontSize: '11px' }}
                    disabled={draftUrl.trim() === osc.oscUrl || !/^wss?:\/\//.test(draftUrl.trim())}
                    onClick={() => osc.setOscUrl(draftUrl.trim())}
                >
                    Apply
                </button>
            </div>
            <div style={{ fontSize: '11px', color: statusColor }} title={osc.oscStatusDetail ?? undefined}>
                ● {STATUS_LABEL[osc.oscStatus]}
            </div>
            {osc.oscEnabled && osc.oscLastAddress && (
                <div style={{ fontSize: '10px', color: '#a0a0b0', fontFamily: 'monospace' }}>last: {osc.oscLastAddress}</div>
            )}
            <div style={{ fontSize: '10px', color: '#a0a0b0' }}>
                Send UDP to the local relay (storage_manager, <code>OSC_RELAY_ENABLED=1</code>, port 9000).
                Addresses: <code>/pixelocity/slot/N/param/x</code>, <code>…/shader</code>, <code>/pixelocity/transition</code>, <code>/pixelocity/audio/amount</code>.
            </div>
        </div>
    );
};

export default OscPanel;
