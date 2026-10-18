import React, { useRef, useState } from 'react';
import type { UseProjectFileReturn } from '../../../hooks/useProjectFile';

export interface ProjectFilePanelProps {
  projectFile: UseProjectFileReturn;
}

export const ProjectFilePanel: React.FC<ProjectFilePanelProps> = ({ projectFile }) => {
  const inputRef = useRef<HTMLInputElement>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [warnings, setWarnings] = useState<string[]>([]);

  const handleExport = () => {
    try {
      const exported = projectFile.exportProject();
      const url = URL.createObjectURL(new Blob([exported.contents], { type: 'application/json' }));
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = exported.filename;
      anchor.click();
      URL.revokeObjectURL(url);
      setWarnings([]);
      setStatus('Project exported');
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Project export failed');
    }
  };

  const handleImport = (file: File) => {
    const reader = new FileReader();
    reader.onload = () => {
      void projectFile.importProject(String(reader.result ?? '')).then(outcome => {
        setWarnings(outcome.warnings);
        setStatus(outcome.ok ? 'Project imported' : outcome.errors.join(' · '));
      });
    };
    reader.onerror = () => setStatus('Project file could not be read');
    reader.readAsText(file);
  };

  return (
    <div className="project-file-panel">
      <div className="project-file-actions">
        <button type="button" className="gold-outline-btn" onClick={handleExport}>
          Export project (.pixelocity.json)
        </button>
        <button type="button" className="gold-outline-btn" onClick={() => inputRef.current?.click()}>
          Import project…
        </button>
      </div>
      <input
        ref={inputRef}
        type="file"
        aria-label="Import project file"
        accept=".pixelocity.json,application/json"
        style={{ display: 'none' }}
        onChange={event => {
          const file = event.target.files?.[0];
          if (file) handleImport(file);
          event.target.value = '';
        }}
      />
      {status && <div className="project-file-status">{status}</div>}
      {warnings.length > 0 && (
        <ul className="project-file-warnings" aria-label="Project import warnings">
          {warnings.map((warning, index) => <li key={`${warning}-${index}`}>{warning}</li>)}
        </ul>
      )}
    </div>
  );
};

export default ProjectFilePanel;
