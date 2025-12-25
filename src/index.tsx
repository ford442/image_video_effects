import React from 'react';
import ReactDOM from 'react-dom/client';
import MainApp from './App';
import RemoteApp from './RemoteApp';

// Check URL parameters to determine which app to render
const urlParams = new URLSearchParams(window.location.search);
const mode = urlParams.get('mode');

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

root.render(
  <React.StrictMode>
    {mode === 'remote' ? <RemoteApp /> : <MainApp />}
  </React.StrictMode>
);
