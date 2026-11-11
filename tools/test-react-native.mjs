import { spawnSync } from 'node:child_process';
import { build } from 'esbuild';
for(const project of ['packages/core/tsconfig.json','packages/react-native/tsconfig.json']){
  const result=spawnSync(process.execPath,['node_modules/typescript/bin/tsc','-p',project],{stdio:'inherit'});
  if(result.status!==0)process.exit(result.status??1);
}
const nativeTypes=spawnSync(process.execPath,['.tools/react-native-0.88/node_modules/typescript/bin/tsc','-p','packages/react-native/tsconfig.native.json'],{stdio:'inherit'});
if(nativeTypes.status!==0)process.exit(nativeTypes.status??1);
await build({entryPoints:['packages/react-native/src/index.ts'],outfile:'packages/react-native/dist/index.js',bundle:true,
  format:'esm',platform:'neutral',target:'es2020',external:['@device-readout/core','react-native']});
await build({entryPoints:['packages/react-native/test/transport.test.mjs'],outfile:'.tools/test/rn-transport.test.mjs',bundle:true,
  format:'esm',platform:'node',target:'es2020',alias:{'@device-readout/core':'./packages/core/dist/index.js'}});
const result=spawnSync(process.execPath,['--test','.tools/test/rn-transport.test.mjs'],{stdio:'inherit'});
process.exit(result.status??1);
