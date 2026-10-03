// ESLint config for `npm run lint` (CI gate) and CRA's build-time plugin.
// The type-aware override needs parserOptions.project, so it only covers files
// that tsconfig.json includes (src/, minus the hand-written wasm_bridge.d.ts).
module.exports = {
  root: true,
  extends: ['react-app', 'react-app/jest'],
  ignorePatterns: ['src/wasm/wasm_bridge.d.ts'],
  settings: {
    // Only treat Testing Library's own render() as a render; renderer tests call
    // unrelated methods named render/switchRenderer that trip the aggressive default.
    'testing-library/custom-renders': 'off',
  },
  overrides: [
    {
      files: ['src/**/*.ts', 'src/**/*.tsx'],
      parserOptions: {
        project: './tsconfig.json',
        tsconfigRootDir: __dirname,
      },
      rules: {
        '@typescript-eslint/no-floating-promises': 'error',
        '@typescript-eslint/no-non-null-assertion': 'warn',
      },
    },
  ],
};
