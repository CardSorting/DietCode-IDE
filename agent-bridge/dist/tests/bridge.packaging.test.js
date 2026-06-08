import { access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';
const here = dirname(fileURLToPath(import.meta.url));
const bridgeRoot = join(here, '..', '..');
const repoRoot = join(bridgeRoot, '..');
describe('bridge.packaging', () => {
    it('packaged bridge artifact exists after make app', async () => {
        const packaged = join(repoRoot, 'build', 'DietCode.app', 'Contents', 'Resources', 'agent-bridge', 'dist', 'index.js');
        const launcher = join(repoRoot, 'build', 'DietCode.app', 'Contents', 'Resources', 'bin', 'dietcode-agent-client');
        await access(packaged);
        await access(launcher);
    });
});
//# sourceMappingURL=bridge.packaging.test.js.map