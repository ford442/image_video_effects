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