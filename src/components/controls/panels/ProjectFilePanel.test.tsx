import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ProjectFilePanel } from './ProjectFilePanel';

describe('ProjectFilePanel', () => {
  it('shows import warnings returned after a project is applied', async () => {
    const importProject = jest.fn().mockResolvedValue({
      ok: true,
      errors: [],
      warnings: ['Unknown shader imported as an empty slot.'],
    });
    render(
      <ProjectFilePanel
        projectFile={{
          exportProject: () => ({ contents: '{}', filename: 'test.pixelocity.json' }),
          importProject,
        }}
      />,
    );
    const input = screen.getByLabelText('Import project file');

    fireEvent.change(input, {
      target: { files: [new File(['{}'], 'test.pixelocity.json', { type: 'application/json' })] },
    });

    await waitFor(() => expect(importProject).toHaveBeenCalledWith('{}'));
    expect(await screen.findByText('Project imported')).toBeTruthy();
    expect(screen.getByText('Unknown shader imported as an empty slot.')).toBeTruthy();
  });
});
