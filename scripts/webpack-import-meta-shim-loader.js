/**
 * Strip import.meta from @xenova/transformers before webpack bundles it.
 * transformers.web.js uses import.meta.url for Node path resolution; in the
 * browser bundle we only need a harmless stub. Without this, webpack 5 emits
 * a mix of literal import.meta and __webpack_module__ references that crash
 * in CRA's classic <script> bundles.
 */
module.exports = function importMetaShimLoader(source) {
  const envStub = '({ NODE_ENV: "production" })';
  const metaStub = `({ url: "", webpack: undefined, env: ${envStub} })`;

  return source
    .replace(/Object\(import\.meta\)/g, metaStub)
    .replace(/import\.meta\.url/g, '""')
    .replace(/import\.meta\.webpack/g, 'undefined')
    .replace(/import\.meta\.env/g, envStub)
    .replace(/import\.meta/g, metaStub);
};
