/**
 * StageOutputHost — always mounted, tiny: loads the stage-output panel (a lazy chunk,
 * with the stage controller) the first time it is opened. Stage windows keep running
 * when the panel is closed; the controller lives on in its module.
 */
import { RefObject, Suspense, lazy, useEffect, useState } from 'react';
import type { RendererManager } from '../../renderer/RendererManager';
import { stagePanelStore } from '../../output/stagePanelStore';

const StageOutputPanel = lazy(() => import(/* webpackChunkName: "stage-outputs" */ './StageOutputPanel'));

export function StageOutputHost({ rendererRef }: { rendererRef?: RefObject<RendererManager | null> }) {
    const [open, setOpen] = useState(stagePanelStore.isOpen());
    useEffect(() => stagePanelStore.subscribe(setOpen), []);
    if (!open || !rendererRef) return null;
    return (
        <Suspense fallback={null}>
            <StageOutputPanel rendererRef={rendererRef} onClose={() => stagePanelStore.setOpen(false)} />
        </Suspense>
    );
}

export default StageOutputHost;
