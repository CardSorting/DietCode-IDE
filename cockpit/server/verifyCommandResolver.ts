import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const FALLBACK = process.env.DIETCODE_AGENT_CHAT_FALLBACK_VERIFY?.trim();

/** Mirror scripts/dietcode_verification_authority.resolve_verify_command */
export function resolveVerifyCommand(
  workspace: string,
  override?: string,
): string | undefined {
  if (override?.trim()) return override.trim();

  const verifySh = join(workspace, 'verify.sh');
  if (existsSync(verifySh)) return './verify.sh';

  const makefile = join(workspace, 'Makefile');
  if (existsSync(makefile)) {
    try {
      const content = readFileSync(makefile, 'utf8');
      if (/^test\s*:/m.test(content)) return 'make test';
    } catch {
      // ignore unreadable Makefile
    }
  }

  const pkgPath = join(workspace, 'package.json');
  if (existsSync(pkgPath)) {
    try {
      const pkg = JSON.parse(readFileSync(pkgPath, 'utf8')) as {
        scripts?: Record<string, string>;
      };
      if (pkg.scripts?.test?.trim()) return 'npm test';
      if (pkg.scripts?.verify?.trim()) return 'npm run verify';
    } catch {
      // ignore invalid package.json
    }
  }

  return FALLBACK || undefined;
}
