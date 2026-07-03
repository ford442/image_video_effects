module.exports = {
  webpack: {
    configure: (webpackConfig, { env, paths }) => {
      webpackConfig.module.rules.push({
        test: /\.m?js$/,
        resolve: {
          fullySpecified: false,
        },
      });

      webpackConfig.ignoreWarnings = [
        { module: /@xenova\/transformers/ }
      ];

      return webpackConfig;
    },
  },
};
