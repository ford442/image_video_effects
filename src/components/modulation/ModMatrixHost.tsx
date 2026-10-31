/**
 * ModMatrixHost — always-mounted, tiny: connects controller events to the modulation bus
 * and loads the mod-matrix panel (a lazy chunk) the first time it is opened (#1513).
 */
import { Suspense, lazy, useEffect, useState } from 'react';
import { connectControlEventsToModulation } from '../../modulation/external';
import { modulationStore } from '../../modulation/store';
import type { ModTarget } from '../../modulation/types';
import type { ShaderEntry } from '../../renderer/types';

const ModMatrixPanel = lazy(() => import(/* webpackChunkName: "mod-matrix" */ './ModMatrixPanel'));

export interface ModMatrixHostProps {
    /** Shader id per slot ('none' / empty for unused slots). */
    modes?: string[];
    availableModes?: ShaderEntry[];
}

export function ModMatrixHost({ modes, availableModes }: ModMatrixHostProps) {
    const [panel, setPanel] = useState<{ open: boolean; target: ModTarget | null }>(() => modulationStore.getPanel());
    useEffect(() => connectControlEventsToModulation(), []);
    useEffect(() => modulationStore.subscribePanel((target, open) => setPanel({ open, target })), []);
    if (!panel.open) return null;
    return (
        <Suspense fallback={null}>
            <ModMatrixPanel
                modes={modes ?? []}
                availableModes={availableModes ?? []}
                initialTarget={panel.target}
                onClose={() => modulationStore.closePanel()}
            />
        </Suspense>
    );
}

export default ModMatrixHost;
