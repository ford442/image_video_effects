// ESLint 9 flat config for `npm run lint` (CI gate).
// Type-aware rules (no-floating-promises) need the TypeScript program, so they only
// cover files that tsconfig.json includes (src/, minus the hand-written wasm_bridge.d.ts).
import js from '@eslint/js';
import globals from 'globals';
import reactHooks from 'eslint-plugin-react-hooks';
import testingLibrary from 'eslint-plugin-testing-library';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['build/**', 'coverage/**', 'public/**', 'node_modules/**', 'src/wasm/wasm_bridge.d.ts'] },
  {
    // A few files carry disable comments for rules this config no longer enables.
    linterOptions: { reportUnusedDisableDirectives: 'off' },
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['src/**/*.{ts,tsx}'],
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
      parserOptions: {
        project: './tsconfig.json',
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: { 'react-hooks': reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-non-null-assertion': 'warn',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      // tsc (noUnusedLocals/Parameters) is the unused-binding gate; keep ESLint quiet about the rest of
      // the recommended set that CRA's react-app config never enforced.
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-empty-object-type': 'off',
      '@typescript-eslint/no-unsafe-function-type': 'off',
      '@typescript-eslint/no-require-imports': 'off',
      '@typescript-eslint/ban-ts-comment': 'off',
      'prefer-const': 'off',
      'no-empty': ['error', { allowEmptyCatch: true }],
      'no-restricted-globals': ['error', 'event', 'name', 'length', 'parent', 'status', 'top'],
    },
  },
  {
    files: ['src/**/*.test.{ts,tsx}', 'src/**/*.spec.{ts,tsx}', 'src/test-utils/**'],
    ...testingLibrary.configs['flat/react'],
    settings: {
      // Only treat Testing Library's own render() as a render; renderer tests call
      // unrelated methods named render/switchRenderer that trip the aggressive default.
      'testing-library/custom-renders': 'off',
    },
    rules: {
      ...testingLibrary.configs['flat/react'].rules,
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
);
