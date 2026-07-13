import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import '@testing-library/jest-dom';
import { VariationGrid } from './VariationGrid';
import { SharedChain } from '../services/layerChainShare';
import { CatalogShader, CatalogParam } from '../services/shaderCatalog';
import { clearFavorites, loadFavorites } from '../services/variationFavorites';

function param(id: string, overrides: Partial<CatalogParam> = {}): CatalogParam {
  return { id, name: id, default: 0.5, min: 0, max: 1, step: 0.01, ...overrides };
}

function shader(id: string, category: string, params: CatalogParam[]): CatalogShader {
  return { id, name: id, category, tags: [], description: '', params, searchText: id };
}

const CATALOG: CatalogShader[] = [
  shader('liquid-a', 'liquid-effects', [param('speed'), param('scale')]),
  shader('liquid-b', 'liquid-effects', [param('tension')]),
  shader('distort-a', 'distortion', [param('amount')]),
  shader('distort-b', 'distortion', [param('strength')]),
];

const BASE_CHAIN: SharedChain = {
  v: 1,
  slots: [
    { shaderId: 'liquid-a', params: { zoomParam1: 0.7 } },
    { shaderId: 'distort-a' },
  ],
};

describe('VariationGrid', () => {
  beforeEach(() => {
    clearFavorites();
  });

  afterEach(() => {
    clearFavorites();
  });

  it('renders N variation cards', () => {
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={4}
        options={{ paramJitter: true, shaderSwap: 'none', seed: 'grid' }}
        onAdopt={jest.fn()}
        onClose={jest.fn()}
      />
    );

    expect(screen.getByTestId('variation-grid-overlay')).toBeInTheDocument();
    for (let i = 0; i < 4; i++) {
      expect(screen.getByTestId(`variation-card-${i}`)).toBeInTheDocument();
      expect(screen.getByTestId(`variation-preview-${i}`)).toBeInTheDocument();
    }
  });

  it('shows shader ids and param summaries in each cell', () => {
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={2}
        options={{ paramJitter: true, shaderSwap: 'none', seed: 'summary' }}
        onAdopt={jest.fn()}
        onClose={jest.fn()}
      />
    );

    for (let i = 0; i < 2; i++) {
      expect(
        screen.getByTestId(`variation-summary-${i}-slot-0`)
      ).toHaveTextContent(/liquid-a/);
      expect(
        screen.getByTestId(`variation-summary-${i}-slot-1`)
      ).toHaveTextContent(/distort-a/);
    }
  });

  it('calls onAdopt with the selected variation chain when Adopt is clicked', () => {
    const onAdopt = jest.fn();
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={3}
        options={{ paramJitter: true, shaderSwap: 'none', seed: 'adopt' }}
        onAdopt={onAdopt}
        onClose={jest.fn()}
      />
    );

    fireEvent.click(screen.getByTestId('adopt-variation-1'));
    expect(onAdopt).toHaveBeenCalledTimes(1);
    const adopted = onAdopt.mock.calls[0][0] as SharedChain;
    expect(adopted.v).toBe(1);
    expect(adopted.slots).toHaveLength(2);
    expect(adopted.slots[0].shaderId).toBe('liquid-a');
    expect(adopted.slots[1].shaderId).toBe('distort-a');
  });

  it('toggles A/B selection', () => {
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={3}
        options={{ paramJitter: false, shaderSwap: 'none', seed: 'ab' }}
        onAdopt={jest.fn()}
        onClose={jest.fn()}
      />
    );

    const checkbox0 = screen.getByRole('checkbox', { name: /Select variation 1 for A\/B/ });
    const checkbox2 = screen.getByRole('checkbox', { name: /Select variation 3 for A\/B/ });

    expect(checkbox0).not.toBeChecked();
    fireEvent.click(checkbox0);
    expect(checkbox0).toBeChecked();
    fireEvent.click(checkbox2);
    expect(checkbox2).toBeChecked();
    fireEvent.click(checkbox0);
    expect(checkbox0).not.toBeChecked();
  });

  it('calls onClose when the close button is clicked', () => {
    const onClose = jest.fn();
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={2}
        options={{ paramJitter: false, shaderSwap: 'none', seed: 'close' }}
        onAdopt={jest.fn()}
        onClose={onClose}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /Close remix explorer/ }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('renders a seed input and reproduces the grid for the same seed', () => {
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={2}
        options={{ paramJitter: true, shaderSwap: 'none', seed: 'seeded' }}
        onAdopt={jest.fn()}
        onClose={jest.fn()}
      />
    );

    const seedInput = screen.getByTestId('seed-input') as HTMLInputElement;
    expect(seedInput).toBeInTheDocument();
    expect(seedInput.value).toBe('seeded');

    const summary0 = screen.getByTestId('variation-summary-0-slot-0').textContent;

    fireEvent.change(seedInput, { target: { value: 'other-seed' } });
    expect(screen.getByTestId('variation-summary-0-slot-0').textContent).not.toBe(summary0);

    fireEvent.change(seedInput, { target: { value: 'seeded' } });
    expect(screen.getByTestId('variation-summary-0-slot-0').textContent).toBe(summary0);
  });

  it('stars a variation and shows it in the favorites strip', () => {
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={2}
        options={{ paramJitter: false, shaderSwap: 'none', seed: 'star' }}
        onAdopt={jest.fn()}
        onClose={jest.fn()}
      />
    );

    expect(loadFavorites()).toHaveLength(0);

    fireEvent.click(screen.getByTestId('star-variation-0'));

    const favorites = loadFavorites();
    expect(favorites).toHaveLength(1);
    expect(favorites[0].name).toBe('Variation #1');
    expect(screen.getByTestId('favorites-strip')).toBeInTheDocument();
    expect(screen.getByTestId(`favorite-item-${favorites[0].id}`)).toBeInTheDocument();
  });

  it('breeds two selected variations into a new grid', () => {
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={4}
        options={{ paramJitter: true, shaderSwap: 'none', seed: 'breed-ui' }}
        onAdopt={jest.fn()}
        onClose={jest.fn()}
      />
    );

    const checkbox0 = screen.getByRole('checkbox', { name: /Select variation 1 for A\/B/ });
    const checkbox1 = screen.getByRole('checkbox', { name: /Select variation 2 for A\/B/ });

    fireEvent.click(checkbox0);
    fireEvent.click(checkbox1);

    const breedButton = screen.getByTestId('breed-selected');
    expect(breedButton).toBeInTheDocument();

    const summaryBefore = screen.getByTestId('variation-summary-0-slot-0').textContent;

    fireEvent.click(breedButton);

    const summaryAfter = screen.getByTestId('variation-summary-0-slot-0').textContent;
    expect(summaryAfter).not.toBe(summaryBefore);
    expect(screen.queryByTestId('breed-selected')).not.toBeInTheDocument();
  });

  it('reseed from chain resets the grid to the base chain', () => {
    render(
      <VariationGrid
        baseChain={BASE_CHAIN}
        catalog={CATALOG}
        count={2}
        options={{ paramJitter: true, shaderSwap: 'none', seed: 'reseed' }}
        onAdopt={jest.fn()}
        onClose={jest.fn()}
      />
    );

    const seedInput = screen.getByTestId('seed-input') as HTMLInputElement;
    const summary0 = screen.getByTestId('variation-summary-0-slot-0').textContent;

    fireEvent.change(seedInput, { target: { value: 'other-seed' } });
    expect(screen.getByTestId('variation-summary-0-slot-0').textContent).not.toBe(summary0);

    fireEvent.click(screen.getByTestId('reseed-from-chain'));
    expect(screen.getByTestId('variation-summary-0-slot-0').textContent).toBe(summary0);
  });
});
