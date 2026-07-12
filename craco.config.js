const path = require('path');

module.exports = {
  webpack: {
    configure: (webpackConfig, { env, paths }) => {
      // Allow dynamic imports
      webpackConfig.experiments = {
        ...webpackConfig.experiments,
        outputModule: true
      };

      webpackConfig.output = {
          ...webpackConfig.output,
          module: true,
          environment: {
              ...webpackConfig.output.environment,
              dynamicImport: true,
              module: true
          }
      };

      // Ensure proper resolution
      webpackConfig.module.rules.unshift({
          test: /\.m?js$/,
          resolve: {
              fullySpecified: false
          }
      });

      return webpackConfig;
    }
  }
};
