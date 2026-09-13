  const path = require('path');
  module.exports = {
    webpack: {
      configure: (webpackConfig) => {
        webpackConfig.module.rules.push({
          test: /\.m?js/,
          resolve: {
            fullySpecified: false,
          },
        });
        // Shim import.meta inside transformers before webpack parses the package.
        webpackConfig.module.rules.unshift({
          test: /\.m?js$/,
          include: /node_modules[\\/]@xenova[\\/]transformers/,
          use: path.resolve(__dirname, 'scripts/webpack-import-meta-shim-loader.js'),
        });
        webpackConfig.experiments = {
          ...webpackConfig.experiments,
          topLevelAwait: true,
        };
        webpackConfig.output = {
          ...webpackConfig.output,
          environment: {
            ...(webpackConfig.output.environment || {}),
            dynamicImport: true,
          },
        };
        webpackConfig.resolve = webpackConfig.resolve || {};
        webpackConfig.resolve.extensionAlias = {
          ...webpackConfig.resolve.extensionAlias,
          '.js': ['.ts', '.tsx', '.js'],
        };
        webpackConfig.resolve.alias = {
          ...webpackConfig.resolve.alias,
          'sharp$': false,
          'onnxruntime-node$': false,
        };
        webpackConfig.ignoreWarnings = [
          /Failed to parse source map/,
          /Critical dependency: 'import.meta'/,
        ];
        return webpackConfig;
      },
    },
    jest: {
      configure: (jestConfig) => {
        // Jest 27 has no webpack extensionAlias. Browser ESM keeps explicit
        // `.js` specifiers in src/wasm/**; map those to the TypeScript files.
        // Prepend so first-match cannot lose to a later generic pattern.
        // Do NOT map all relative `.js` to `$1.ts` — that remaps node_modules
        // CJS (e.g. ./cjs/react-is.development.js) and Jest throws Configuration error.
        jestConfig.moduleNameMapper = {
          '^src/wasm/bridge/(.+)\\.js$': '<rootDir>/src/wasm/bridge/$1.ts',
          '^src/wasm/wasm_bridge\\.js$': '<rootDir>/src/wasm/wasm_bridge.ts',
          '^\\./bridge/(.+)\\.js$': '<rootDir>/src/wasm/bridge/$1.ts',
          '^\\./(capture|diagnostics|init|recording|shader|state|uniforms|wgslFormat)\\.js$':
            '<rootDir>/src/wasm/bridge/$1.ts',
          ...jestConfig.moduleNameMapper,
          // Extensionless fallback for other TS ESM `.js` specifiers. `$1.ts` is too broad.
          '^(\\.{1,2}/.+)\\.js$': '$1',
        };
        return jestConfig;
      },
    },
  };