module.exports = {
  webpack: {
    configure: (webpackConfig) => {
      webpackConfig.module.rules.push({
        test: /\.m?js/,
        resolve: {
          fullySpecified: false,
        },
      });

      webpackConfig.experiments = {
        ...webpackConfig.experiments,
        topLevelAwait: true,
        outputModule: true
      };

      webpackConfig.module.rules.push({
        test: /\.m?js$/,
        parser: {
          javascript: {
            importMeta: false
          }
        }
      });

      webpackConfig.ignoreWarnings = [/Failed to parse source map/, /Critical dependency: 'import.meta'/];
      return webpackConfig;
    },
  },
};
