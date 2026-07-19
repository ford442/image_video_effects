/**
 * Tests for the community preset-pack API client.
 * All HTTP traffic is mocked so the suite runs offline.
 */

import {
  publishPack,
  listCommunityPacks,
  getCommunityPack,
  recordPresetPackPlay,
  getCommunityPackWithDecodedChain,
} from './communityGallery';
import { encodeChain, decodeChain, SharedChain } from './layerChainShare';

const API_URL = 'https://storage.noahcohn.com';

describe('communityGallery', () => {
  const fetchMock = jest.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  function makeChain(shaderId: string = 'liquid-metal'): SharedChain {
    return {
      v: 1,
      slots: [
        { shaderId, params: { zoomParam1: 0.35 } },
        { shaderId: 'liquid-rainbow' },
      ],
    };
  }

  describe('publishPack', () => {
    it('POSTs an encoded chain to /api/preset-packs', async () => {
      const chain = makeChain();
      const encoded = encodeChain(chain);

      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          success: true,
          id: 'pack-123',
          pack: {
            id: 'pack-123',
            name: 'Liquid Dreams',
            description: 'desc',
            author: 'tester',
            date: '2026-07-11',
            chain: encoded,
            play_count: 0,
          },
        }),
      });

      const result = await publishPack({
        name: 'Liquid Dreams',
        description: 'desc',
        author: 'tester',
        chain,
      });

      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/api/preset-packs`,
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({ 'Content-Type': 'application/json' }),
          body: expect.any(String),
        })
      );

      const body = JSON.parse(fetchMock.mock.calls[0][1]!.body as string);
      expect(body.name).toBe('Liquid Dreams');
      expect(body.description).toBe('desc');
      expect(body.author).toBe('tester');
      expect(body.chain).toBe(encoded);
      expect(result.pack.id).toBe('pack-123');
    });

    it('throws when the backend rejects the chain', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: false,
        status: 400,
        statusText: 'Bad Request',
        json: async () => ({ detail: 'Invalid shared chain' }),
      });

      await expect(
        publishPack({ name: 'Bad', chain: makeChain() })
      ).rejects.toThrow('Invalid shared chain');
    });
  });

  describe('listCommunityPacks', () => {
    it('GETs /api/preset-packs with optional query params', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          total: 1,
          limit: 10,
          offset: 0,
          packs: [
            {
              id: 'pack-1',
              name: 'Pack One',
              description: '',
              author: 'a',
              date: '2026-07-11',
              chain: encodeChain(makeChain()),
              play_count: 0,
            },
          ],
        }),
      });

      const result = await listCommunityPacks({ limit: 10, offset: 0 });
      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/api/preset-packs?limit=10&offset=0`,
        expect.objectContaining({ method: 'GET' })
      );
      expect(result.total).toBe(1);
      expect(result.packs[0].name).toBe('Pack One');
    });

    it('omits query params when no options are given', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ total: 0, limit: 50, offset: 0, packs: [] }),
      });

      await listCommunityPacks();
      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/api/preset-packs`,
        expect.objectContaining({ method: 'GET' })
      );
    });

    it('passes sort_by when sortBy is provided', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ total: 0, limit: 50, offset: 0, packs: [] }),
      });

      await listCommunityPacks({ limit: 50, sortBy: 'play_count' });
      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/api/preset-packs?limit=50&sort_by=play_count`,
        expect.objectContaining({ method: 'GET' })
      );
    });
  });

  describe('getCommunityPack', () => {
    it('GETs /api/preset-packs/{id}', async () => {
      const chain = makeChain();
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          id: 'pack-1',
          name: 'Pack One',
          description: '',
          author: 'a',
          date: '2026-07-11',
          chain: encodeChain(chain),
          play_count: 0,
        }),
      });

      const result = await getCommunityPack('pack-1');
      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/api/preset-packs/pack-1`,
        expect.objectContaining({ method: 'GET' })
      );
      expect(result.name).toBe('Pack One');
    });

    it('throws on 404', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: false,
        status: 404,
        statusText: 'Not Found',
        json: async () => ({ detail: 'Preset pack not found' }),
      });

      await expect(getCommunityPack('missing')).rejects.toThrow('Preset pack not found');
    });
  });

  describe('recordPresetPackPlay', () => {
    it('POSTs to /api/preset-packs/{id}/play', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          success: true,
          id: 'pack-1',
          play_count: 7,
          last_played: '2026-07-11T20:00:00',
        }),
      });

      const result = await recordPresetPackPlay('pack-1');
      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/api/preset-packs/pack-1/play`,
        expect.objectContaining({ method: 'POST' })
      );
      expect(result.play_count).toBe(7);
    });
  });

  describe('round-trip contract', () => {
    it('publishPack -> getCommunityPack preserves the SharedChain', async () => {
      const original: SharedChain = {
        v: 1,
        slots: [
          { shaderId: 'liquid-metal', params: { zoomParam1: 0.35, lightStrength: 1.2 } },
          { shaderId: 'liquid-rainbow', enabled: false, mode: 'parallel' },
          { shaderId: null },
        ],
      };
      const encoded = encodeChain(original);

      fetchMock
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            success: true,
            id: 'roundtrip-pack',
            pack: {
              id: 'roundtrip-pack',
              name: 'Round Trip',
              description: '',
              author: 'contract',
              date: '2026-07-11',
              chain: encoded,
              play_count: 0,
            },
          }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            id: 'roundtrip-pack',
            name: 'Round Trip',
            description: '',
            author: 'contract',
            date: '2026-07-11',
            chain: encoded,
            play_count: 0,
          }),
        });

      const publishResult = await publishPack({ name: 'Round Trip', author: 'contract', chain: original });
      expect(publishResult.pack.chain).toBe(encoded);

      const fetched = await getCommunityPackWithDecodedChain(publishResult.id);
      expect(fetched).not.toBeNull();
      expect(fetched!.chain).toEqual(original);
      expect(decodeChain(fetched!.pack.chain)).toEqual(original);
    });
  });
});
