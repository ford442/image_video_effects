import React from 'react';
import ReactDOM from 'react-dom/client';
import MainApp from './App';
import RemoteApp from './RemoteApp';
import ShaderValidator from './components/ShaderValidator';
import { shouldMountRemoteApp } from './utils/publicHost';

// Check URL parameters to determine which app to render
const urlParams = new URLSearchParams(window.location.search);
const isValidator = urlParams.has('validator');
const mountRemote = shouldMountRemoteApp(window.location.search, window.location.hostname);
const stageOutput = urlParams.get('mode') === 'stage' ? urlParams.get('output') : null;

if (stageOutput !== null) {
  // Stage window (docs/STAGE_OUTPUTS.md): one canvas handed to the control window's
  // renderer; no React UI, no renderer of its own.
  void import(/* webpackChunkName: "stage" */ './output/stagePage').then(({ mountStage }) => {
    mountStage(window, /^[a-z0-9][a-z0-9-]{0,31}$/.test(stageOutput) ? stageOutput : 'stage-1');
  });
} else {
  const root = ReactDOM.createRoot(
    document.getElementById('root') as HTMLElement
  );

  root.render(
    <React.StrictMode>
      {isValidator ? <ShaderValidator /> : mountRemote ? <RemoteApp /> : <MainApp />}
    </React.StrictMode>
  );
}
