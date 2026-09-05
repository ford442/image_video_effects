import {
  hasHealthyThumbnailInManifest,
  hasThumbnailInManifest,
  parseUnhealthyIds,
} from './useThumbnailManifest';

describe('useThumbnailManifest helpers', () => {
  const manifest = {
    healthy: { thumbnail_url: 'thumbnails/healthy.png' },
    black: { thumbnail_url: 'thumbnails/black.png' },
  };
  const unhealthy = new Set(['black']);

  it('parseUnhealthyIds reads ids array', () => {
    expect([...parseUnhealthyIds({ ids: ['a', 'b'] })].sort()).toEqual(['a', 'b']);
  });

  it('hasThumbnailInManifest is URL presence only', () => {
    expect(hasThumbnailInManifest(manifest, 'healthy')).toBe(true);
    expect(hasThumbnailInManifest(manifest, 'black')).toBe(true);
    expect(hasThumbnailInManifest(manifest, 'missing')).toBe(false);
  });

  it('hasHealthyThumbnailInManifest excludes flagged ids', () => {
    expect(hasHealthyThumbnailInManifest(manifest, 'healthy', unhealthy)).toBe(true);
    expect(hasHealthyThumbnailInManifest(manifest, 'black', unhealthy)).toBe(false);
    expect(hasHealthyThumbnailInManifest(manifest, 'missing', unhealthy)).toBe(false);
  });
});
