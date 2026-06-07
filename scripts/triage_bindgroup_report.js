'use strict';

const fs   = require('fs');
const path = require('path');

const REPO_ROOT   = path.join(__dirname, '..');
const REPORT_PATH = path.join(REPO_ROOT, 'reports/bindgroup_compatibility_report.json');
const SWARM_STATE = path.join(REPO_ROOT, '.swarm-state.md');
const TRIAGE_OUT  = path.join(REPO_ROOT, 'reports/bindgroup_triage.md');
const QUEUE_OUT   = path.join(REPO_ROOT, 'reports/bindgroup_fix_queue.json');

// Maximum characters kept from a raw error string when building preview examples
const MAX_ERROR_PREVIEW_LENGTH = 200;

// Root-cause categories — initial set, extensible.
// Patterns are tested in order; first match wins.
const CATEGORIES = [
  // Explicit "incompatible type" wording used by bindgroup_checker.py
  { key: 'TYPE_MISMATCH',
    rx: /(incompatible\s+type|(type|resource).*?(does not match|expected|but got))/i },
  // "missing fields" (uniforms struct) or classic WebGPU "no binding provided" phrasing
  { key: 'MISSING_BINDING',
    rx: /(missing\s+fields?|(no binding provided|not present in).*?(group|binding))/i },
  { key: 'LAYOUT_SIZE_MISMATCH',
    rx: /size.*?(smaller than|minimum expected)/i },
  { key: 'VISIBILITY_MISMATCH',
    rx: /visibility.*?(does not include|expected)/i },
  { key: 'SAMPLE_TYPE_MISMATCH',
    rx: /sample types?.*?(do not match|expected)/i },
  // Missing entry points (bindgroup_checker: "No @compute … entry points found")
  // and classic pipeline-layout errors from Naga/Tint
  { key: 'PIPELINE_LAYOUT_MISMATCH',
    rx: /(entry\s+points?\s+(not\s+found|found)|no\s+@?(compute|vertex|fragment)\s+entry\s+point|error matching (FRAGMENT|VERTEX|COMPUTE).*against the pipeline)/i },
];

/**
 * Return the base type name before any WGSL generic parameters.
 *   "texture_2d<f32>"            -> "texture_2d"
 *   "array<PlasmaBall, 50>"      -> "array"
 *   "texture_storage_2d<rgba8>"  -> "texture_storage_2d"
 * Using indexOf avoids CodeQL's incomplete-multi-character-sanitization rule.
 */
const canonicalize = (t) => {
  if (typeof t !== 'string') return 'unknown';
  const angleBracketIdx = t.indexOf('<');
  const base = angleBracketIdx !== -1 ? t.slice(0, angleBracketIdx) : t;
  return base.trim() || 'unknown';
};

/**
 * Extract group / binding numbers from a raw error string.
 * Handles patterns like:
 *   "ResourceBinding { group: 0, binding: 2 }"
 *   "entries[3]"
 *   "Binding 12 (foo)"
 */
const extractFields = (errorString = '') => {
  const groupMatch   = errorString.match(/group[\[\s:]*(\d+)/i);
  const bindingMatch = errorString.match(/binding[\[\s:]*(\d+)/i);
  return {
    group:   groupMatch   ? parseInt(groupMatch[1],   10) : null,
    binding: bindingMatch ? parseInt(bindingMatch[1], 10) : null,
  };
};

/** Return the category key for a raw error string. */
const categorize = (errorString = '') => {
  for (const c of CATEGORIES) {
    if (c.rx.test(errorString)) return c.key;
  }
  return 'UNKNOWN_ERROR';
};

/**
 * Parse the shader IDs fixed in the 2026-05-09 swarm pass from .swarm-state.md.
 * Lines look like: "1/49 astral-kaleidoscope: FIXED (…)"
 * The count (49) is not hard-coded; any N/M prefix is accepted so the regex
 * stays valid if the file is later amended with additional entries.
 */
const parseFixedShaderIds = () => {
  try {
    const md = fs.readFileSync(SWARM_STATE, 'utf8');
    const ids = new Set();
    md.split('\n').forEach(line => {
      const m = line.match(/^\d+\/\d+\s+([a-z0-9-]+):/i);
      if (m) ids.add(m[1]);
    });
    return ids;
  } catch (_) {
    return new Set();
  }
};

/**
 * Normalize the {shaders:[...]} format produced by bindgroup_checker.py
 * into a flat list of virtual entry objects matching the generic schema
 * expected by the rest of the script.
 *
 * Each shader.errors[] element becomes one entry.
 * Each shader.missing_bindings[] element that has no corresponding error
 * string also becomes one entry (to avoid dropping structured data).
 */
const flattenShaders = (shaders) => {
  const entries = [];

  for (const shader of (shaders ?? [])) {
    if (!shader) continue;   // skip null/undefined shader slots
    const id = shader?.shader_id ?? shader?.shaderId ?? shader?.id ?? 'unknown';

    // Build a binding-number → wrong-type-info lookup for context enrichment
    const wrongTypeMap = {};
    for (const wb of (shader?.wrong_type_bindings ?? [])) {
      if (wb?.binding != null) wrongTypeMap[String(wb.binding)] = wb;
    }

    const emittedErrors = new Set();

    // Primary source: error strings
    for (const rawErr of (shader?.errors ?? [])) {
      // Defensively coerce to string — null/undefined entries should not throw
      const errStr = rawErr != null ? String(rawErr) : '';
      if (!errStr) continue;
      emittedErrors.add(errStr);

      // Enrich context from wrong_type_bindings when the error mentions a binding
      const bindingMatch = errStr.match(/\bBinding\s+(\d+)\b/i);
      const bindingKey   = bindingMatch ? bindingMatch[1] : null;
      const wrongType    = bindingKey != null ? wrongTypeMap[bindingKey] : null;

      entries.push({
        shaderName: id,
        error: errStr,
        context: {
          group:        0,                                          // all engine bindings are group 0
          binding:      bindingKey != null ? parseInt(bindingKey, 10) : null,
          actualType:   wrongType?.found_type ?? null,
          expectedType: null,                                       // not present in this report format
        },
      });
    }

    // Secondary source: missing_bindings (structured; may not have a corresponding error string)
    for (const mb of (shader?.missing_bindings ?? [])) {
      const syntheticError =
        `Missing binding ${mb?.binding} (${mb?.name ?? 'unknown'}) not provided for group 0`;
      if (!emittedErrors.has(syntheticError)) {
        entries.push({
          shaderName: id,
          error: syntheticError,
          context: {
            group:        0,
            binding:      mb?.binding ?? null,
            expectedType: mb?.expected_type ?? null,
            actualType:   null,
          },
        });
      }
    }
  }

  return entries;
};

const main = () => {
  // ── 1. Read report ────────────────────────────────────────────────────────
  let raw;
  try {
    raw = fs.readFileSync(REPORT_PATH, 'utf8');
  } catch (e) {
    console.error(`Cannot read ${REPORT_PATH}: ${e.message}`);
    process.exit(1);
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    console.error(`Malformed JSON in report: ${e.message}`);
    process.exit(1);
  }

  // ── 2. Normalize to flat entry list (schema-resilient) ───────────────────
  let entries;
  if (Array.isArray(parsed)) {
    // Format A: flat array of error objects (Naga/Tint pipeline output)
    entries = parsed;
  } else if (Array.isArray(parsed?.shaders)) {
    // Format B: { shaders: [...] } from bindgroup_checker.py
    // Only flatten shaders that actually have errors to report
    entries = flattenShaders(parsed.shaders.filter(s => (s?.errors?.length ?? 0) > 0));
  } else {
    // Format C: { errors: [...] } or { entries: [...] } fallbacks
    const fallback = parsed?.errors ?? parsed?.entries ?? null;
    if (!Array.isArray(fallback)) {
      console.error('Report JSON has no recognizable array of entries');
      process.exit(1);
    }
    entries = fallback;
  }

  // ── 3. Load May-16 fix-pass shader IDs ───────────────────────────────────
  const fixedIds = parseFixedShaderIds();

  // ── 4. Process entries ────────────────────────────────────────────────────
  const groups   = new Map();
  const rejected = [];
  const queue    = [];

  entries.forEach((entry, idx) => {
    try {
      const errStr  = entry?.error ?? entry?.errorString ?? entry?.message ?? '';
      const shader  = entry?.shaderName ?? entry?.shader ?? entry?.shaderId ?? 'unknown';
      const ctx     = entry?.context ?? {};
      const fields  = extractFields(errStr);

      const group   = ctx.group   ?? fields.group;
      const binding = ctx.binding ?? fields.binding;
      const exp     = canonicalize(
        ctx?.expected?.type ?? ctx?.expectedType ?? ctx?.expected ?? null,
      );
      const act     = canonicalize(
        ctx?.actual?.type ?? ctx?.actualType ?? ctx?.actual ?? null,
      );
      const cat      = categorize(errStr);
      const key      = `${cat}:g${group ?? '?'}:${exp}\u2192${act}`;
      const wasFixed = fixedIds.has(shader);

      if (!groups.has(key)) {
        groups.set(key, {
          key, category: cat, group, expected: exp, actual: act,
          occurrences: 0, shaders: new Set(), examples: [],
        });
      }
      const g = groups.get(key);
      g.occurrences += 1;
      g.shaders.add(shader);
      if (g.examples.length < 3) {
        g.examples.push({ shader, error: errStr.slice(0, MAX_ERROR_PREVIEW_LENGTH) });
      }

      queue.push({
        shader, rootCauseKey: key, category: cat, group, binding,
        expected: exp, actual: act, rawError: errStr,
        wasInMay16FixPass: wasFixed,
      });
    } catch (e) {
      rejected.push({ index: idx, reason: e.message, raw: entry });
    }
  });

  // ── 5. Compute priority scores ────────────────────────────────────────────
  // Priority = (shadersAffected × 10) + occurrenceCount
  // This surfaces fixes that unblock the most shaders while still weighting
  // noisy single-shader issues by frequency.
  for (const g of groups.values()) {
    g.shadersAffected = g.shaders.size;
    g.priorityScore   = g.shadersAffected * 10 + g.occurrences;
    g.shaders         = [...g.shaders].sort();
  }

  const sortedGroups = [...groups.values()].sort(
    (a, b) => b.priorityScore - a.priorityScore,
  );

  // ── 6. Sort queue: unfixed first, then by group priority, then shader name ─
  queue.sort((a, b) => {
    if (a.wasInMay16FixPass !== b.wasInMay16FixPass) {
      return a.wasInMay16FixPass ? 1 : -1;
    }
    const sa = groups.get(a.rootCauseKey)?.priorityScore ?? 0;
    const sb = groups.get(b.rootCauseKey)?.priorityScore ?? 0;
    if (sa !== sb) return sb - sa;
    return a.shader.localeCompare(b.shader);
  });

  // ── 7. Build markdown report ──────────────────────────────────────────────
  const may16Count = queue.filter(q => q.wasInMay16FixPass).length;

  let md = `# Bind-Group Compatibility Triage\n\n`;
  md += `Generated: ${new Date().toISOString()}\n\n`;
  md += `- Total entries: **${queue.length}**\n`;
  md += `- Distinct root causes: **${sortedGroups.length}**\n`;
  md += `- Rejected (unparseable): **${rejected.length}**\n`;
  md += `- Entries from May-16 fix pass shaders: **${may16Count}**\n\n`;
  md += `## Root causes by priority\n\n`;
  md += `| Priority | Category | Group | Expected \u2192 Actual | Shaders | Occurrences | Sample shaders |\n`;
  md += `|---|---|---|---|---|---|---|\n`;
  for (const g of sortedGroups) {
    const extraCount = g.shaders.length > 3 ? ` (+${g.shaders.length - 3})` : '';
    const sample     = g.shaders.slice(0, 3).join(', ') + extraCount;
    md += `| ${g.priorityScore} | ${g.category} | ${g.group ?? '?'} | `;
    md += `\`${g.expected}\` \u2192 \`${g.actual}\` | `;
    md += `${g.shadersAffected} | ${g.occurrences} | ${sample} |\n`;
  }

  // ── 8. Build JSON fix queue ───────────────────────────────────────────────
  const queueOut = {
    _meta: {
      generated:          new Date().toISOString(),
      totalEntries:       queue.length,
      distinctRootCauses: sortedGroups.length,
      rejected,
      fixedShaderIdsCount: fixedIds.size,
    },
    rootCauses: sortedGroups,
    queue,
  };

  // ── 9. Write outputs ──────────────────────────────────────────────────────
  fs.writeFileSync(TRIAGE_OUT, md, 'utf8');
  fs.writeFileSync(QUEUE_OUT,  JSON.stringify(queueOut, null, 2), 'utf8');

  console.log(`\u2713 ${queue.length} entries, ${sortedGroups.length} root causes, ${rejected.length} rejected`);
  console.log(`\u2713 wrote ${TRIAGE_OUT}`);
  console.log(`\u2713 wrote ${QUEUE_OUT}`);
};

main();
