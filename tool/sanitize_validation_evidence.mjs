import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, copyFileSync, realpathSync, lstatSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

// Evidence-only mechanical normalization. Never alter source, outcomes or Git history.
// Run before release_sensitivity_check.dart; that independent gate stays authoritative.
const args = process.argv.slice(2);
if (args.some(arg => arg !== '--write') || args.length > 1) {
  throw new Error('Usage: node tool/sanitize_validation_evidence.mjs [--write]');
}
const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const paths = execFileSync('git', [
  'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', 'docs/validation/',
], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean);
const replacements = [
  [/\/Users\/[A-Za-z0-9._-]+\//g, '<home>/'],
  [/\/home\/[A-Za-z0-9._-]+\//g, '<home>/'],
  [/[A-Za-z]:\\(?:\\)?Users\\(?:\\)?[A-Za-z0-9._-]+\\(?:\\)?/g, '<home>/'],
];
const changes = [];
for (const path of new Set(paths)) {
  const absolute = resolve(root, path);
  if (!absolute.startsWith(join(root, 'docs/validation/'))) throw new Error('Unexpected evidence path');
  let bytes;
  try {
    if (lstatSync(absolute).isSymbolicLink() || !realpathSync(absolute).startsWith(join(realpathSync(root), 'docs/validation/'))) {
      throw new Error(`Evidence path escapes its ownership boundary: ${path}`);
    }
    bytes = readFileSync(absolute);
  }
  catch (error) { if (error.code === 'ENOENT') continue; throw error; }
  if (bytes.includes(0)) continue;
  const source = bytes.toString('utf8');
  // Do not damage a binary or malformed UTF-8 file.
  if (!Buffer.from(source).equals(bytes)) continue;
  let normalized = source;
  for (const [pattern, replacement] of replacements) normalized = normalized.replace(pattern, replacement);
  if (normalized !== source) changes.push({ path, normalized, bytes });
}
if (args.includes('--write') && changes.length) {
  const backup = mkdtempSync(join(tmpdir(), 'ccrouter-evidence-originals-'));
  // Back up every original before changing any file; backup remains outside the repository.
  for (const { path, bytes } of changes) {
    if (!readFileSync(join(root, path)).equals(bytes)) throw new Error('Evidence changed during normalization; retry after recording stops');
    const target = join(backup, path);
    mkdirSync(dirname(target), { recursive: true });
    copyFileSync(join(root, path), target);
  }
  writeFileSync(join(backup, 'manifest.json'), JSON.stringify({ root, files: changes.map(c => c.path) }, null, 2));
  for (const { path, normalized } of changes) writeFileSync(join(root, path), normalized);
  console.log(`Normalized ${changes.length} evidence files. Recoverable originals: ${backup}`);
} else {
  console.log(`Evidence files requiring path normalization: ${changes.length}`);
  if (changes.length) process.exitCode = 1;
}
