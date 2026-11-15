import { createRef } from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import type { RendererManager } from '../../renderer/RendererManager';
import { resetStageControllerForTests } from '../../output/stageController';
import { StageOutputPanel } from './StageOutputPanel';

function managerWithBackend(withBackend: boolean) {
  const ref = createRef<RendererManager | null>() as { current: RendererManager | null };
  const backend = {
    attachOutput: vi.fn(async () => ({ ok: true })),
    detachOutput: vi.fn(),
    setOutputConfig: vi.fn(),
    setOutputSize: vi.fn(),
    getOutputStatus: vi.fn(() => []),
  };
  ref.current = {
    getOutputBackend: () => (withBackend ? backend : null),
    onBackendReady: vi.fn(() => () => undefined),
  } as unknown as RendererManager;
  return { ref, backend };
}

describe('StageOutputPanel', () => {
  afterEach(() => resetStageControllerForTests());

  it('opens a stage window and shows its calibration card', () => {
    const { ref } = managerWithBackend(true);
    const stageWin = { closed: false, postMessage: vi.fn(), focus: vi.fn(), close: vi.fn() };
    const open = vi.spyOn(window, 'open').mockReturnValue(stageWin as unknown as Window);
    render(<StageOutputPanel rendererRef={ref} onClose={() => undefined} />);
    expect(ref.current?.onBackendReady).toHaveBeenCalled();
    fireEvent.click(screen.getByText('Open stage window'));
    expect(open).toHaveBeenCalledWith(expect.stringContaining('mode=stage&output=stage-1'), 'pixelocity-stage-stage-1', expect.any(String));
    expect(screen.getByText('stage-1')).toBeTruthy();
    expect(screen.getByLabelText('Test pattern')).toBeTruthy();
    expect(screen.getByLabelText(/Corner pin for stage-1/)).toBeTruthy();
    open.mockRestore();
  });

  it('explains that stage outputs need the WebGPU renderer', () => {
    const { ref } = managerWithBackend(false);
    render(<StageOutputPanel rendererRef={ref} onClose={() => undefined} />);
    expect(screen.getByRole('alert').textContent).toMatch(/WebGPU renderer/);
    expect((screen.getByText('Open stage window') as HTMLButtonElement).disabled).toBe(true);
  });
});
