import React, { useMemo, useState } from 'react';
import { EntryCatalog, EntryOption, searchEntries } from '../../graphLab/entryCatalog';

const SOURCE_LABEL: Record<EntryOption['source'], string> = {
  catalog: 'catalog',
  'graph-entry': 'graph entry',
  'chain-pass': 'chain pass',
};

export interface EntryPickerProps {
  /** null while the shader catalog is still loading: entries are then typed in freely. */
  catalog: EntryCatalog | null;
  /** Current entry; shown above the search box. */
  value?: string;
  placeholder?: string;
  disabled?: boolean;
  onPick: (entry: string) => void;
}

/** Search the WGSL files a node can run (file stems under public/shaders/). */
export function EntryPicker({ catalog, value, placeholder = 'Search shader entries…', disabled, onPick }: EntryPickerProps) {
  const [query, setQuery] = useState('');
  const results = useMemo(() => (catalog && query.trim() ? searchEntries(catalog, query, 40) : []), [catalog, query]);

  const pick = (entry: string) => {
    onPick(entry);
    setQuery('');
  };

  return (
    <div className="graph-lab__picker" data-testid="entry-picker">
      {value !== undefined && (
        <div className="graph-lab__picker-current">
          entry <code>{value || '—'}</code>
        </div>
      )}
      <input
        type="search"
        value={query}
        disabled={disabled}
        placeholder={catalog ? placeholder : 'Catalog loading — type an entry id and press Enter'}
        aria-label="Search shader entries"
        data-testid="entry-picker-input"
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.key !== 'Enter') return;
          const typed = query.trim();
          if (results[0]) pick(results[0].entry);
          else if (!catalog && typed) pick(typed);
        }}
      />
      {catalog && !query.trim() && (
        <div className="graph-lab__hint">{catalog.options.length.toLocaleString()} entries — type to search</div>
      )}
      {catalog && query.trim() && results.length === 0 && <div className="graph-lab__hint">No entry matches “{query}”.</div>}
      {results.length > 0 && (
        <ul className="graph-lab__results" role="listbox" aria-label="Matching entries">
          {results.map((option) => (
            <li key={option.entry} role="option" aria-selected={option.entry === value}>
              <button
                type="button"
                disabled={disabled}
                data-testid={`entry-option-${option.entry}`}
                onClick={() => pick(option.entry)}
              >
                <span className="graph-lab__result-entry">{option.entry}</span>
                {option.label !== option.entry && <span className="graph-lab__result-label">{option.label}</span>}
                <span className={`graph-lab__tag graph-lab__tag--${option.source}`}>{SOURCE_LABEL[option.source]}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
