/**
 * Load thumbnail skip allowlist — shaders excluded from generation queue and coverage denominator.
 */
const fs = require('fs');
const path = require('path');

const ALLOWLIST_PATH = path.join(__dirname, '..', '..', 'reports', 'thumbnail_skip_allowlist.json');

function loadThumbnailSkipIds() {
  if (!fs.existsSync(ALLOWLIST_PATH)) return new Set();
  const data = JSON.parse(fs.readFileSync(ALLOWLIST_PATH, 'utf8'));
  return new Set((data.ids || []).filter(Boolean));
}

module.exports = { loadThumbnailSkipIds, ALLOWLIST_PATH };
