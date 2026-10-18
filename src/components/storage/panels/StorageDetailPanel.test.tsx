import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { StorageDetailPanel } from './StorageDetailPanel';

describe('StorageDetailPanel', () => {
  it('renders nothing when closed', () => {
    const { container } = render(
      <StorageDetailPanel isOpen={false} item={null} onClose={vi.fn()} />,
    );
    expect(container).toBeEmptyDOMElement();
  });

  it('shows preview content when open', () => {
    render(
      <StorageDetailPanel
        isOpen
        item={{
          id: 'test-shader',
          name: 'Test Shader',
          type: 'shader',
          description: 'A test',
        }}
        onClose={vi.fn()}
      />,
    );
    expect(screen.getByText('Test Shader')).toBeInTheDocument();
    expect(screen.getByText('Live WebGPU preview')).toBeInTheDocument();
  });
});
