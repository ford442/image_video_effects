import React from 'react';
import { render, screen } from '@testing-library/react';
import { PassFlameStrip, passColor } from './PassFlameStrip';
import type { PassTiming } from '../../../renderer/passTimings';

const pass = (over: Partial<PassTiming>): PassTiming => ({
  key: 'k',
  label: 'node',
  kind: 'compute',
  slot: 0,
  scale: 1,
  gpuMs: 1,
  iterations: 1,
  ...over,
});

describe('PassFlameStrip', () => {
  it('draws one segment per pass and lists the heaviest first', () => {
    render(
      <PassFlameStrip
        source="gpu-timestamp"
        topN={2}
        passes={[
          pass({ key: '0:step', label: 'step', gpuMs: 3, iterations: 3 }),
          pass({ key: '1:blur', label: 'blur', slot: 1, gpuMs: 0.5, scale: 0.5 }),
          pass({ key: 'present', label: 'present', kind: 'present', slot: undefined, gpuMs: 0.5 }),
        ]}
      />,
    );
    expect(screen.getAllByTestId('pass-flame-segment')).toHaveLength(3);
    expect(screen.getByText(/Per-pass GPU · 4\.00 ms/)).toBeTruthy();
    expect(screen.getByText('slot 1 · step ×3')).toBeTruthy();
    expect(screen.getByText(/3\.00 ms · 75%/)).toBeTruthy();
    expect(screen.queryByText('present')).toBeNull(); // topN = 2, tie keeps the earlier pass
    expect(screen.getByText('slot 2 · blur @50%')).toBeTruthy();
  });

  it('explains why there is no data', () => {
    const { rerender } = render(<PassFlameStrip passes={[]} source="wall-clock" />);
    expect(screen.getByTestId('pass-flame-strip').textContent).toContain('unavailable');
    rerender(<PassFlameStrip passes={[]} source="gpu-timestamp" />);
    expect(screen.getByTestId('pass-flame-strip').textContent).toContain('waiting for timestamps');
  });

  it('colors fixed passes by kind and compute passes by slot', () => {
    expect(passColor({ kind: 'present' })).not.toEqual(passColor({ kind: 'compute', slot: 0 }));
    expect(passColor({ kind: 'compute', slot: 0 })).toEqual(passColor({ kind: 'compute', slot: 6 }));
  });
});
