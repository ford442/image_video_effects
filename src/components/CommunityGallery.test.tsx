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

  function setupFetchHandlers(options: {
    manifest?: Record<string, { thumbnail_url: string }>;
    listPacks?: ReturnType<typeof makePack>[];
    listError?: boolean;
  } = {}) {
    fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
      if (url.includes('manifest.json')) {
        return { ok: true, json: async () => options.manifest ?? {} };
      }
      if (url.includes('/play')) {
        return {
          ok: true,
          json: async () => ({ success: true, id: 'pack-1', play_count: 1, last_played: 'now' }),
        };
      }
      if (url.includes('/api/preset-packs')) {
        if (init?.method === 'POST') {
          const body = JSON.parse(init.body as string);
          const chain = makeChain('liquid-metal');
          return {
            ok: true,
            json: async () => ({
              success: true,
              id: 'new-pack',
              pack: makePack('new-pack', body.name, chain),
            }),
          };
        }
        if (options.listError) {
          return {
            ok: false,
            status: 500,
            statusText: 'Internal Server Error',
            json: async () => ({ detail: 'boom' }),
          };
        }
        const packs = options.listPacks ?? [];
        return {
          ok: true,
          json: async () => ({ total: packs.length, limit: 50, offset: 0, packs }),
        };
      }
      throw new Error(`unexpected fetch: ${url}`);
    });
  }

  function renderGallery(props: Partial<CommunityGalleryProps> = {}) {
    const defaultProps: CommunityGalleryProps = {
      open: false,
      onToggle: jest.fn(),
      onApplySharedChain: jest.fn(),
      getCurrentChain: () => makeChain(),
    };
    return render(<CommunityGallery {...defaultProps} {...props} />);
  }

  it('does not fetch while collapsed', () => {
    renderGallery({ open: false });
    expect(global.fetch).not.toHaveBeenCalled();
    expect(screen.getByText('Community Gallery')).toBeInTheDocument();
  });

  it('fetches and lists community packs when opened', async () => {
    setupFetchHandlers({
      listPacks: [
        makePack('pack-1', 'Pack One', makeChain('liquid-metal')),
        makePack('pack-2', 'Pack Two', makeChain('cosmic-flow')),
      ],
    });

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

  it('renders a thumbnail when the manifest has an entry for the first slot shader', async () => {
    setupFetchHandlers({
      manifest: {
        'liquid-metal': { thumbnail_url: 'thumbnails/liquid-metal.png' },
      },
      listPacks: [makePack('pack-1', 'Pack One', makeChain('liquid-metal'))],
    });

    renderGallery({ open: true });

    await waitFor(() => expect(screen.getByText('Pack One')).toBeInTheDocument());
    const img = document.querySelector('img[src="./thumbnails/liquid-metal.png"]');
    expect(img).toBeInTheDocument();
  });

  it('omits thumbnail image when manifest has no entry for the first slot shader', async () => {
    setupFetchHandlers({
      manifest: {},
      listPacks: [makePack('pack-1', 'Pack One', makeChain('unknown-shader'))],
    });

    renderGallery({ open: true });

    await waitFor(() => expect(screen.getByText('Pack One')).toBeInTheDocument());
    expect(document.querySelector('img')).toBeNull();
  });

  it('invokes onApplySharedChain when Load Pack is clicked and records play', async () => {
    const chain = makeChain('liquid-metal');
    setupFetchHandlers({ listPacks: [makePack('pack-1', 'Pack One', chain)] });

    const onApplySharedChain = jest.fn();
    renderGallery({ open: true, onApplySharedChain });

    await waitFor(() => expect(screen.getByText('Pack One')).toBeInTheDocument());
    fireEvent.click(screen.getByText('Load Pack'));

    await waitFor(() => expect(onApplySharedChain).toHaveBeenCalled());
    expect(onApplySharedChain).toHaveBeenCalledWith(chain);
    expect(global.fetch).toHaveBeenCalledWith(
      `${API_URL}/api/preset-packs/pack-1/play`,
      expect.objectContaining({ method: 'POST' })
    );
  });

  it('shows an error state when the list fetch fails', async () => {
    setupFetchHandlers({ listError: true });

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
    setupFetchHandlers({ listPacks: [] });
    renderGallery({ open: true });

    await waitFor(() =>
      expect(screen.getByText('No community packs yet — be the first!')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByText('Publish current chain'));

    expect(screen.getByPlaceholderText('Pack name')).toBeInTheDocument();
    expect(screen.getByText('Publish')).toBeInTheDocument();
  });

  it('publishes the current chain and refreshes the list', async () => {
    const chain = makeChain('liquid-metal');
    const encoded = encodeChain(chain);
    let listCallCount = 0;

    fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
      if (url.includes('manifest.json')) {
        return { ok: true, json: async () => ({}) };
      }
      if (init?.method === 'POST' && url.endsWith('/api/preset-packs')) {
        const body = JSON.parse(init.body as string);
        return {
          ok: true,
          json: async () => ({
            success: true,
            id: 'new-pack',
            pack: makePack('new-pack', body.name, chain),
          }),
        };
      }
      if (url.includes('/api/preset-packs')) {
        listCallCount += 1;
        const packs =
          listCallCount === 1 ? [] : [makePack('new-pack', 'My New Pack', chain)];
        return {
          ok: true,
          json: async () => ({ total: packs.length, limit: 50, offset: 0, packs }),
        };
      }
      throw new Error(`unexpected fetch: ${url}`);
    });

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

    const publishCall = fetchMock.mock.calls.find(
      call => String(call[0]).endsWith('/api/preset-packs') && call[1]?.method === 'POST'
    );
    expect(publishCall).toBeDefined();
    const body = JSON.parse(publishCall![1]!.body as string);
    expect(body.name).toBe('My New Pack');
    expect(body.author).toBe('Tester');
    expect(body.description).toBe('A test pack');
    expect(body.chain).toBe(encoded);
  });

  it('shows an error when there is no current chain to publish', async () => {
    setupFetchHandlers({ listPacks: [] });
    renderGallery({ open: true, getCurrentChain: () => null });

    await waitFor(() =>
      expect(screen.getByText('No community packs yet — be the first!')).toBeInTheDocument()
    );
    fireEvent.click(screen.getByText('Publish current chain'));

    await waitFor(() =>
      expect(screen.getByText('No chain is currently loaded to publish.')).toBeInTheDocument()
    );
  });

  it('round-trip: publish → list → apply decodes original chain', async () => {
    const chain = makeChain('liquid-metal');
    const pack = makePack('rt-pack', 'Round Trip Pack', chain);
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    let listCallCount = 0;

    fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
      if (url.includes('manifest.json')) {
        return { ok: true, json: async () => ({}) };
      }
      if (init?.method === 'POST' && url.endsWith('/api/preset-packs')) {
        return {
          ok: true,
          json: async () => ({ success: true, id: pack.id, pack }),
        };
      }
      if (init?.method === 'POST' && url.includes('/play')) {
        return {
          ok: true,
          json: async () => ({
            success: true,
            id: pack.id,
            play_count: 1,
            last_played: 'now',
          }),
        };
      }
      if (url.includes('/api/preset-packs')) {
        listCallCount += 1;
        const packs = listCallCount === 1 ? [] : [pack];
        return {
          ok: true,
          json: async () => ({ total: packs.length, limit: 50, offset: 0, packs }),
        };
      }
      throw new Error(`unexpected fetch: ${url}`);
    });

    const onApplySharedChain = jest.fn();
    renderGallery({ open: true, getCurrentChain: () => chain, onApplySharedChain });

    await waitFor(() =>
      expect(screen.getByText('No community packs yet — be the first!')).toBeInTheDocument()
    );

    fireEvent.click(screen.getByText('Publish current chain'));
    fireEvent.change(screen.getByPlaceholderText('Pack name'), {
      target: { value: 'Round Trip Pack' },
    });
    fireEvent.click(screen.getByText('Publish'));

    await waitFor(() => expect(screen.getByText('Round Trip Pack')).toBeInTheDocument());

    fireEvent.click(screen.getAllByText('Load Pack')[0]);

    await waitFor(() => expect(onApplySharedChain).toHaveBeenCalledWith(chain));

    const shaderIds = chain.slots.map(s => s.shaderId).join(',');
    console.log(
      `[CommunityGallery E2E] publish=${pack.id} list=1 apply=ok shaders=${shaderIds}`
    );

    expect(logSpy).toHaveBeenCalledWith(
      `[CommunityGallery E2E] publish=${pack.id} list=1 apply=ok shaders=${shaderIds}`
    );

    logSpy.mockRestore();
  });
});
