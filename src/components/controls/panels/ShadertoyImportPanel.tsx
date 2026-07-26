import React, { useState, useCallback } from 'react';
import { ShadertoyImporter } from '../../shaders/ShadertoyImporter';
import { ShadertoyGallery } from '../../shaders/ShadertoyGallery';
import { ShaderImportResult } from '../../../services/shaderApi';
import {
  convertShadertoyGlsl,
  generateShaderDefinitionDraft,
  type ShaderDefinitionDraft,
} from '../../../services/shadertoyToPixelocity';
import { checkWgslGatePreview } from '../../../utils/wgslGatePreview';
import { StorageClient } from '../../../services/storage/client';

export interface ShadertoyImportPanelProps {
  onPreviewShader?: (id: string, wgsl: string, name: string) => void;
  onStatus?: (message: string) => void;
}

type ImportTab = 'id' | 'paste' | 'search';

export const ShadertoyImportPanel: React.FC<ShadertoyImportPanelProps> = ({
  onPreviewShader,
  onStatus,
}) => {
  const [tab, setTab] = useState<ImportTab>('id');
  const [pasteGlsl, setPasteGlsl] = useState('');
  const [previewWgsl, setPreviewWgsl] = useState('');
  const [previewName, setPreviewName] = useState('');
  const [previewId, setPreviewId] = useState('');
  const [gateResult, setGateResult] = useState<ReturnType<typeof checkWgslGatePreview> | null>(null);
  const [busy, setBusy] = useState(false);
  const [uploadBusy, setUploadBusy] = useState(false);

  const runConversion = useCallback(async (glsl: string, name: string, id: string) => {
    setBusy(true);
    setGateResult(null);
    onStatus?.('Converting GLSL → WGSL…');
    try {
      const result = await convertShadertoyGlsl(glsl);
      if (result.errors.length > 0) {
        onStatus?.(`❌ ${result.errors.join('; ')}`);
        setPreviewWgsl('');
        return;
      }
      const gate = checkWgslGatePreview(result.wgsl);
      setPreviewWgsl(result.wgsl);
      setPreviewName(name);
      setPreviewId(id);
      setGateResult(gate);
      if (gate.ok) {
        onStatus?.(`✅ Gate preview passed${result.warnings.length ? ` (${result.warnings.length} warnings)` : ''}`);
      } else {
        onStatus?.(`❌ Gate preview failed: ${gate.errors.join('; ')}`);
      }
    } catch (err) {
      onStatus?.(`❌ ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setBusy(false);
    }
  }, [onStatus]);

  const handleApiImport = useCallback(async (result: ShaderImportResult) => {
    const glsl = result.meta.glsl_code;
    if (!glsl) {
      onStatus?.('Import succeeded but no GLSL returned — paste source manually');
      return;
    }
    await runConversion(glsl, result.name, result.id);
  }, [runConversion, onStatus]);

  const handlePasteConvert = useCallback(() => {
    if (!pasteGlsl.trim()) return;
    const id = previewId || `import-${Date.now()}`;
    const name = previewName || 'Pasted Shader';
    void runConversion(pasteGlsl, name, id);
  }, [pasteGlsl, previewId, previewName, runConversion]);

  const handleLoadPreview = useCallback(() => {
    if (!previewWgsl || !gateResult?.ok) return;
    const id = previewId || `import-preview-${Date.now()}`;
    onPreviewShader?.(id, previewWgsl, previewName || id);
    onStatus?.(`Preview loaded: ${previewName || id}`);
  }, [previewWgsl, gateResult, previewId, previewName, onPreviewShader, onStatus]);

  const handleUploadVps = useCallback(async () => {
    if (!previewWgsl || !gateResult?.ok) return;
    setUploadBusy(true);
    try {
      const draft = generateShaderDefinitionDraft(previewId || 'imported-shader', previewName || 'Imported');
      const client = new StorageClient();
      await client.saveShader(draft.name, previewWgsl, {
        id: draft.id,
        description: draft.description,
        tags: draft.tags,
      });
      onStatus?.(`📦 Uploaded to VPS: ${draft.name}`);
    } catch (err) {
      onStatus?.(`Upload failed: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setUploadBusy(false);
    }
  }, [previewWgsl, gateResult, previewId, previewName, onStatus]);

  const draftJson: ShaderDefinitionDraft | null = previewId && previewName
    ? generateShaderDefinitionDraft(previewId, previewName)
    : null;

  return (
    <div className="shadertoy-import-panel" style={{ marginTop: '10px' }}>
      <div className="gold-section-header" style={{ fontSize: '12px' }}>Shadertoy Import</div>
      <p style={{ fontSize: '10px', color: '#a0a0b0', margin: '4px 0 8px' }}>
        v1: single-pass Image shaders only (no iChannel1–3). Save locally via{' '}
        <code style={{ fontSize: '9px' }}>python3 scripts/accept_imported_shader.py</code>
      </p>

      <div style={{ display: 'flex', gap: '4px', marginBottom: '8px' }}>
        {(['id', 'paste', 'search'] as ImportTab[]).map((t) => (
          <button
            key={t}
            type="button"
            className={tab === t ? 'gold-btn' : 'gold-outline-btn'}
            style={{ flex: 1, fontSize: '10px', padding: '4px 6px' }}
            onClick={() => setTab(t)}
          >
            {t === 'id' ? 'By ID' : t === 'paste' ? 'Paste GLSL' : 'Search'}
          </button>
        ))}
      </div>

      {tab === 'id' && (
        <ShadertoyImporter
          onImport={(r) => { void handleApiImport(r); }}
          onError={(e) => onStatus?.(`Import error: ${e.message}`)}
          className="!p-3 !rounded-lg"
        />
      )}

      {tab === 'paste' && (
        <div>
          <input
            placeholder="Shader name"
            value={previewName}
            onChange={(e) => setPreviewName(e.target.value)}
            className="w-full mb-2 p-2 bg-black/30 rounded text-white text-sm"
          />
          <textarea
            placeholder="Paste Shadertoy GLSL (mainImage + helpers)"
            value={pasteGlsl}
            onChange={(e) => setPasteGlsl(e.target.value)}
            rows={6}
            className="w-full mb-2 p-2 bg-black/30 rounded text-white text-xs font-mono"
          />
          <button
            type="button"
            className="gold-btn w-full"
            disabled={busy || !pasteGlsl.trim()}
            onClick={handlePasteConvert}
          >
            {busy ? 'Converting…' : 'Convert to WGSL'}
          </button>
        </div>
      )}

      {tab === 'search' && (
        <ShadertoyGallery
          onImported={(id) => onStatus?.(`Imported ${id} — fetch GLSL via API tab if needed`)}
        />
      )}

      {previewWgsl && (
        <div style={{ marginTop: '10px' }}>
          <div style={{ fontSize: '11px', color: gateResult?.ok ? '#4ade80' : '#f87171', marginBottom: '4px' }}>
            Gate: {gateResult?.ok ? 'PASS' : 'FAIL'}
            {gateResult?.warnings?.length ? ` (${gateResult.warnings.length} warnings)` : ''}
          </div>
          {gateResult?.errors?.map((e) => (
            <div key={e} style={{ fontSize: '10px', color: '#f87171' }}>{e}</div>
          ))}
          <textarea
            readOnly
            value={previewWgsl}
            rows={8}
            className="w-full p-2 bg-black/40 rounded text-white text-xs font-mono"
            style={{ maxHeight: '160px' }}
          />
          <div style={{ display: 'flex', gap: '6px', marginTop: '6px', flexWrap: 'wrap' }}>
            <button
              type="button"
              className="gold-btn"
              style={{ flex: 1, fontSize: '11px' }}
              disabled={!gateResult?.ok}
              onClick={handleLoadPreview}
            >
              Load on canvas
            </button>
            <button
              type="button"
              className="gold-outline-btn"
              style={{ flex: 1, fontSize: '11px' }}
              disabled={!gateResult?.ok || uploadBusy}
              onClick={() => { void handleUploadVps(); }}
            >
              {uploadBusy ? 'Uploading…' : 'Upload VPS'}
            </button>
          </div>
          {draftJson && gateResult?.ok && (
            <p style={{ fontSize: '9px', color: '#a0a0b0', marginTop: '6px' }}>
              Local catalog: copy WGSL then run{' '}
              <code>python3 scripts/accept_imported_shader.py --id {draftJson.id} --name &quot;{draftJson.name}&quot; --stdin</code>
            </p>
          )}
        </div>
      )}
    </div>
  );
};

export default ShadertoyImportPanel;
