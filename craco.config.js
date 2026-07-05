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

      // topLevelAwait is required by transformers.js / onnxruntime-web.
      // Do NOT set outputModule: true or importMeta: false — CRA serves classic
      // script bundles; leaving import.meta in the output causes a runtime crash:
      //   Uncaught SyntaxError: Cannot use 'import.meta' outside a module
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

      // Block Node-only backends from being bundled into the browser build.
      webpackConfig.resolve = webpackConfig.resolve || {};
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
};
