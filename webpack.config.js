const webpack = require('webpack');
const path = require('path');

module.exports = {
  entry: './src/main.ts',
  experiments: {
    topLevelAwait: true,
    outputModule: true,
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
      {
        test: /\.m?js$/,
        include: path.resolve(__dirname, 'node_modules/@xenova/transformers'),
        type: 'javascript/esm',
        resolve: {
          fullySpecified: false,
        },
      },
    ],
  },
  resolve: {
    extensions: ['.ts', '.js'],
  },
  output: {
    filename: 'main.bundle.js',
    path: path.resolve(__dirname, 'dist'),
  },
  mode: 'development',
  watch: true,
  plugins: [
    new webpack.DefinePlugin({
      'import.meta.env': 'import.meta.env',
    }),
  ],
};
