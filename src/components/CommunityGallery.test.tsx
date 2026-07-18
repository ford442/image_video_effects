import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import { CommunityGallery, CommunityGalleryProps } from './CommunityGallery';
import { encodeChain, SharedChain } from '../services/layerChainShare';

const API_URL = 'https://storage.noahcohn.com';

function makeChain(name: string = 'liquid-metal'): SharedChain {
  return {
    v: 1,
    slots: [{ shaderId: name }, { shaderId: 'liquid-rainbow' }],
  };
}

function makePack(id: string, name: string, chain: SharedChain) {
  return {
    id,
    name,
    description: `Description for ${name}`,
    author: 'tester',
    date: '2026-07-11',
    chain: encodeChain(chain),
    play_count: 0,
  };
}

describe('CommunityGallery', () => {
  const fetchMock = jest.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  function renderGallery(props: Partial<CommunityGalleryProps> = {}) {
    const defaultProps: CommunityGalleryProps = {
      open: false,
      onToggle: jest.fn(),
      onApplySharedChain: jest.fn(),
      getCurrentChain: () => makeChain(),
    };
    return render(<CommunityGallery {...defaultProps} {...props} />);
  }

  function mockListResponse(packs: ReturnType<typeof makePack>[]) {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ total: packs.length, limit: 50, offset: 0, packs }),
    });
  }

  it('does not fetch while collapsed', () => {
    renderGallery({ open: false });
    expect(global.fetch).not.toHaveBeenCalled();
    expect(screen.getByText('Community Gallery')).toBeInTheDocument();
  });

  it('fetches and lists community packs when opened', async () => {
    mockListResponse([
      makePack('pack-1', 'Pack One', makeChain('liquid-metal')),
      makePack('pack-2', 'Pack Two', makeChain('cosmic-flow')),
    ]);

    renderGallery({ open: true });

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith(
        `${API_URL}/api/preset-packs?limit=50&sort_by=play_count`,
        expect.any(Object)
      )
    );
    await waitFor(() => expect(screen.getByText('Pack One')).toBeInTheDocument());
    expect(screen.getByText('Pack Two')).toBeInTheDocument();
    expect(screen.getByText('Description for Pack One')).toBeInTheDocument();
  });

  it('invokes onApplySharedChain when Load Pack is clicked and records play', async () => {
    const chain = makeChain('liquid-metal');
    mockListResponse([makePack('pack-1', 'Pack One', chain)]);
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ success: true, id: 'pack-1', play_count: 1, last_played: 'now' }),
    });

    const onApplySharedChain = jest.fn();
    renderGallery({ open: true, onApplySharedChain });

    await waitFor(() => expect(screen.getByText('Pack One')).toBeInTheDocument());
    fireEvent.click(screen.getByText('Load Pack'));

    await waitFor(() => expect(onApplySharedChain).toHaveBeenCalled());
    expect(onApplySharedChain).toHaveBeenCalledWith(chain);
    expect(global.fetch).toHaveBeenLastCalledWith(
      `${API_URL}/api/preset-packs/pack-1/play`,
      expect.objectContaining({ method: 'POST' })
    );
  });

  it('shows an error state when the list fetch fails', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 500,
      statusText: 'Internal Server Error',
      json: async () => ({ detail: 'boom' }),
    });

    renderGallery({ open: true });

    await waitFor(() =>
      expect(screen.getByText(/Couldn’t load community packs/)).toBeInTheDocument()
    );
  });

  it('calls onToggle when the header is clicked', () => {
    const onToggle = jest.fn();
    renderGallery({ open: false, onToggle });
    fireEvent.click(screen.getByText('Community Gallery'));
    expect(onToggle).toHaveBeenCalled();
  });

  it('opens a publish form when Publish current chain is clicked', async () => {
    mockListResponse([]);
    renderGallery({ open: true });

    await waitFor(() =>
      expect(screen.getByText('No community packs yet — be the first!')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByText('Publish current chain'));

    expect(screen.getByPlaceholderText('Pack name')).toBeInTheDocument();
    expect(screen.getByText('Publish')).toBeInTheDocument();
  });

  it('publishes the current chain and refreshes the list', async () => {
    mockListResponse([]);
    const chain = makeChain('liquid-metal');
    const encoded = encodeChain(chain);

    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        success: true,
        id: 'new-pack',
        pack: makePack('new-pack', 'My New Pack', chain),
      }),
    });

    // refresh after publish
    mockListResponse([makePack('new-pack', 'My New Pack', chain)]);

    renderGallery({ open: true, getCurrentChain: () => chain });

    await waitFor(() =>
      expect(screen.getByText('No community packs yet — be the first!')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByText('Publish current chain'));

    fireEvent.change(screen.getByPlaceholderText('Pack name'), {
      target: { value: 'My New Pack' },
    });
    fireEvent.change(screen.getByPlaceholderText('Author (optional)'), {
      target: { value: 'Tester' },
    });
    fireEvent.change(screen.getByPlaceholderText('Description (optional)'), {
      target: { value: 'A test pack' },
    });

    fireEvent.click(screen.getByText('Publish'));

    await waitFor(() => expect(screen.getByText('My New Pack')).toBeInTheDocument());

    const publishCall = fetchMock.mock.calls.find(call =>
      String(call[0]).endsWith('/api/preset-packs')
    );
    expect(publishCall).toBeDefined();
    const body = JSON.parse(publishCall![1]!.body as string);
    expect(body.name).toBe('My New Pack');
    expect(body.author).toBe('Tester');
    expect(body.description).toBe('A test pack');
    expect(body.chain).toBe(encoded);
  });

  it('shows an error when there is no current chain to publish', async () => {
    mockListResponse([]);
    renderGallery({ open: true, getCurrentChain: () => null });

    await waitFor(() =>
      expect(screen.getByText('No community packs yet — be the first!')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByText('Publish current chain'));

    await waitFor(() =>
      expect(screen.getByText('No chain is currently loaded to publish.')).toBeInTheDocument()
    );
  });
});
