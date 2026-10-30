import type { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const sourcePolicyPlugin: HvigorPlugin = {
  pluginId: 'mianyu-source-policy',
  apply(node: HvigorNode): void {
    node.registerTask({
      name: 'verifySourcePolicy',
      postDependencies: ['default@PreBuild'],
      run(): void {
        const checkerPath = resolve(node.getNodeDir().getPath(), '../tools/verify-source-policy.mjs');
        execFileSync(process.execPath, [checkerPath], { stdio: 'inherit' });
      }
    });
  }
};

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [sourcePolicyPlugin] /* Custom plugins to extend the functionality of Hvigor. */
}
