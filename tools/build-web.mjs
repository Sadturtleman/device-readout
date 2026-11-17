import { build } from 'esbuild';
await build({entryPoints:['packages/web/src/dart-worker.ts'],outfile:'packages/web/dist/dart-worker.js',bundle:true,
  format:'esm',target:'es2020',platform:'browser',sourcemap:true,
  alias:{'@device-readout/core/collector':'./packages/core/dist/collector.js'}});
await build({entryPoints:['packages/web/src/index.ts'],outfile:'packages/web/dist/index.js',bundle:true,
  format:'esm',target:'es2020',platform:'browser',external:['@device-readout/core'],sourcemap:true});
await build({entryPoints:['packages/web/src/worker.ts'],outfile:'packages/web/dist/worker.js',bundle:true,
  format:'esm',target:'es2020',platform:'browser',sourcemap:true,
  alias:{'@device-readout/core/collector':'./packages/core/dist/collector.js'}});
await build({entryPoints:['packages/web/src/browser-collector.ts'],outfile:'.tools/test/browser-collector.mjs',bundle:true,
  format:'esm',target:'es2020',platform:'node',
  alias:{'@device-readout/core/collector':'./packages/core/dist/collector.js'}});
