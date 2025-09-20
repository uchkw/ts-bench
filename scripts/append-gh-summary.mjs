import { existsSync, readFileSync, appendFileSync } from 'node:fs';
import { EOL } from 'node:os';

// Allow overriding the summary input and output paths for easier local testing.
const [summaryArg, outputArg] = process.argv.slice(2);
const summaryFile = summaryArg ?? 'benchmark-summary.txt';
const ghaSummaryPath = outputArg ?? process.env.GITHUB_STEP_SUMMARY;

if (!existsSync(summaryFile) || !ghaSummaryPath) {
  process.exit(0);
}

const content = readFileSync(summaryFile, 'utf-8');
const lines = content.split(/\r?\n/);
const marker = '📈 Benchmark Results';
const markerIndex = lines.findIndex(line => line.trim() === marker);

if (markerIndex === -1) {
  process.exit(0);
}

let startIndex = markerIndex;
if (markerIndex > 0) {
  const previousLine = lines[markerIndex - 1];
  if (previousLine && previousLine.replace(/=/g, '') === '') {
    startIndex = markerIndex - 1;
  }
}

const block = lines.slice(startIndex).join('\n').trimEnd();
if (!block) {
  process.exit(0);
}

const snippet = `${EOL}\u0060\u0060\u0060${EOL}${block}${EOL}\u0060\u0060\u0060${EOL}`;
appendFileSync(ghaSummaryPath, snippet, 'utf-8');
