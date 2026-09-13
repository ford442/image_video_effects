import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { ShaderGallery } from './ShaderGallery';
import { useSemanticShaderSearch } from '../hooks/useSemanticShaderSearch';

jest.mock('../hooks/useThumbnailManifest', () => ({
  useThumbnailManifest: () => ({
    manifest: { halftone: { thumbnail_url: 'thumbnails/halftone.png' } },
    loading: false,
    hasThumbnail: (id: string) => id === 'halftone',
    hasHealthyThumbnail: (id: string) => id === 'halftone',
  }),
}));

jest.mock('../hooks/useSemanticShaderSearch', () => ({
  useSemanticShaderSearch: jest.fn(() => ({ status: 'off', hits: null })),
}));

const mockSemantic = useSemanticShaderSearch as jest.MockedFunction<typeof useSemanticShaderSearch>;

beforeAll(() => {
  (global as unknown as { IntersectionObserver: unknown }).IntersectionObserver = class {
    observe() {}
    disconnect() {}
  };
});

const options = [
  { id: 'halftone', name: 'Retro Halftone', coordinate: null, category: 'retro-glitch' },
  { id: 'ferrofluid-spikes', name: 'Ferrofluid Spikes', coordinate: null, category: 'simulation' },
  { id: 'plasma', name: 'Plasma', coordinate: null, category: 'generative' },
];

function names() {
  return screen.queryAllByText(/Halftone|Ferrofluid|Plasma/, { selector: '.shader-gallery-name' }).map(n => n.textContent);
}

describe('ShaderGallery search', () => {
  beforeEach(() => mockSemantic.mockReturnValue({ status: 'off', hits: null }));

  it('uses the substring filter when no semantic hits are available', () => {
    render(<ShaderGallery options={options} onSelect={jest.fn()} onClose={jest.fn()} />);
    fireEvent.change(screen.getByPlaceholderText('Search shaders...'), { target: { value: 'ferro' } });
    expect(names()).toEqual(['Ferrofluid Spikes']);
  });

  it('orders results by semantic rank when hits arrive', () => {
    mockSemantic.mockReturnValue({
      status: 'ready',
      hits: [
        { id: 'plasma', score: 0.4 },
        { id: 'halftone', score: 0.3 },
      ],
    });
    render(<ShaderGallery options={options} onSelect={jest.fn()} onClose={jest.fn()} />);
    expect(names()).toEqual(['Plasma', 'Retro Halftone']);
  });

  it('dev "Needs thumb" filter hides shaders with a healthy thumbnail', () => {
    render(<ShaderGallery options={options} onSelect={jest.fn()} onClose={jest.fn()} />);
    fireEvent.click(screen.getByLabelText('Needs thumb'));
    expect(names()).toEqual(['Ferrofluid Spikes', 'Plasma']);
  });
});
