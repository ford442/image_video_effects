module.exports = {
  webpack: {
    configure: (webpackConfig) => {
      // Find the rule that handles node_modules
      webpackConfig.module.rules.push({
        test: /\.m?js/,
        resolve: {
          fullySpecified: false,
        },
      });
      // Enable topLevelAwait for @xenova/transformers
      webpackConfig.experiments = {
        ...webpackConfig.experiments,
        topLevelAwait: true,
        outputModule: true
      };

      // Add rule to ignore the import.meta warning since @xenova/transformers wraps it in Object(import.meta)
      // which causes webpack to emit a Critical Dependency warning.
      // This is a known issue with webpack 5 and @xenova/transformers.
      // https://github.com/xenova/transformers.js/issues/304
      webpackConfig.module.rules.push({
        test: /node_modules[\\/]@xenova[\\/]transformers[\\/]dist[\\/]/,
        parser: {
          javascript: {
            importMeta: false
          }
        }
      });

      return webpackConfig;
    },
  },
};
