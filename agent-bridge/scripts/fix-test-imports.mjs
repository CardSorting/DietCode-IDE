import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = join(import.meta.dirname, '..', 'dist', 'tests');
for (const file of readdirSync(dir)) {
  if (!file.endsWith('.js')) continue;
  const path = join(dir, file);
  const text = readFileSync(path, 'utf8');
  const fixed = text.replaceAll('../dist/', '../');
  if (fixed !== text) writeFileSync(path, fixed);
}
