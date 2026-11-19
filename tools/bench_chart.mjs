// Dev-time only: `node tools/bench_chart.mjs [build/bench/results.json]` draws the README's speed
// charts from the results of tests/bench/run.sh: docs/bench/<set>.svg, one per set of rules, a
// panel per project (each with its own scale), a bar per tool. veslint's bar is the accent, the
// others gray; the value is at the tip of each bar. The SVGs follow the viewer's color scheme.
import fs from 'node:fs';
import path from 'node:path';

const root = path.join(import.meta.dirname, '..');
const results = JSON.parse(fs.readFileSync(process.argv[2] ?? path.join(root, 'build/bench/results.json'), 'utf8'));
const outDir = path.join(root, 'docs/bench');
fs.mkdirSync(outDir, { recursive: true });

const TOOLS = [
  ['eslint', 'ESLint'],
  ['veslint', 'veslint'],
  ['oxlint', 'oxlint'],
  ['biome', 'Biome'],
];
const PROJECTS = [
  ['zod', 'zod'],
  ['recharts', 'recharts'],
  ['typescript', 'TypeScript compiler'],
];
const SETS = {
  syntactic: 'Rules without types: 56 rules of @eslint/js and typescript-eslint recommended',
  floating: 'Type-aware linting: no-floating-promises',
  typed: 'Type-aware linting: the 23 type-aware rules of recommendedTypeChecked',
};

const WIDTH = 760;
const PAD = 24;
const LABEL = 92; // the tool names
const VALUE = 250; // room for the value (and how it compares with ESLint's problems) after the longest bar
const BAR = 18;
const ROW = 28;
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const seconds = s => (s < 1 ? s.toFixed(2) : s < 10 ? s.toFixed(1) : s.toFixed(0)) + ' s';
const thousands = n => n.toLocaleString('en-US');

// A bar from x0 growing right by w: square at the baseline, 4px rounded at its end.
function bar(x0, y, w, h, cls) {
  const r = Math.min(4, w / 2, h / 2);
  return `<path class="${cls}" d="M${x0},${y}h${w - r}a${r},${r} 0 0 1 ${r},${r}v${h - 2 * r}a${r},${r} 0 0 1 -${r},${r}h-${w - r}z"/>`;
}

for (const [set, title] of Object.entries(SETS)) {
  const rows = results.results.filter(r => r.set === set);
  if (rows.length === 0) continue;
  const parts = [];
  let y = PAD;
  parts.push(`<text class="title" x="${PAD}" y="${y + 14}">${esc(title)}</text>`);
  y += 22;
  const m = results.machine;
  parts.push(`<text class="sub" x="${PAD}" y="${y + 12}">${esc(`Wall-clock time, mean of ${rows[0].runs} runs (less is better). ${m.cpu.replace(/\s+@.*/, '').replace(/\(R\)|\(TM\)/g, '')}, ${m.cpus} CPUs, ${m.os.split(' ')[0]}. Each panel has its own scale.`)}</text>`);
  y += 30;
  for (const [project, projectName] of PROJECTS) {
    const projectRows = TOOLS.map(([tool, name]) => [name, rows.find(r => r.project === project && r.tool === tool)]).filter(([, r]) => r);
    if (projectRows.length === 0) continue;
    const info = results.projects[project];
    parts.push(`<text class="panel" x="${PAD}" y="${y + 13}">${esc(projectName)}<tspan class="sub" dx="8">${thousands(info.files)} files, ${thousands(info.lines)} lines</tspan></text>`);
    y += 24;
    const max = Math.max(...projectRows.map(([, r]) => r.mean));
    const x0 = PAD + LABEL;
    const span = WIDTH - x0 - VALUE - PAD;
    const top = y;
    for (const [name, r] of projectRows) {
      const w = Math.max(2, (r.mean / max) * span);
      const accent = r.tool === 'veslint';
      parts.push(`<text class="${accent ? 'tool accent-text' : 'tool'}" x="${x0 - 10}" y="${y + BAR / 2 + 5}" text-anchor="end">${esc(name)}</text>`);
      parts.push(bar(x0, y, w, BAR, accent ? 'accent' : 'rest'));
      // How the problems compare with ESLint's: the same ones, or how many of ESLint's it reports.
      const same = r.problems === r.eslintProblems && r.matching === r.eslintProblems;
      const parity = r.tool === 'eslint' ? '' : same ? 'same problems as ESLint' : `${thousands(r.matching)} of ESLint's ${thousands(r.eslintProblems)} problems`;
      parts.push(`<text class="value" x="${x0 + w + 8}" y="${y + BAR / 2 + 5}">${esc(seconds(r.mean))}${parity ? `<tspan class="parity" dx="8">${esc(parity)}</tspan>` : ''}</text>`);
      y += ROW;
    }
    parts.push(`<line class="axis" x1="${x0}" y1="${top - 4}" x2="${x0}" y2="${y - ROW + BAR + 4}"/>`);
    y += 16;
  }
  const height = y + PAD - 16;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${height}" viewBox="0 0 ${WIDTH} ${height}" role="img" aria-label="${esc(title)}">
<style>
  svg { --surface: #fcfcfb; --ink: #0b0b0b; --ink2: #52514e; --axis: #c3c2b7; --accent: #2a78d6; --rest: #898781; }
  @media (prefers-color-scheme: dark) {
    svg { --surface: #1a1a19; --ink: #f0efec; --ink2: #c3c2b7; --axis: #383835; --accent: #3987e5; --rest: #898781; }
  }
  .bg { fill: var(--surface); }
  text { font-family: system-ui, -apple-system, "Segoe UI", sans-serif; fill: var(--ink); }
  .title { font-size: 16px; font-weight: 600; }
  .sub { font-size: 12px; fill: var(--ink2); font-weight: 400; }
  .panel { font-size: 14px; font-weight: 600; }
  .tool { font-size: 13px; }
  .accent-text { font-weight: 700; }
  .value { font-size: 13px; fill: var(--ink2); font-variant-numeric: tabular-nums; }
  .parity { font-size: 12px; fill: var(--ink2); }
  .accent { fill: var(--accent); }
  .rest { fill: var(--rest); }
  .axis { stroke: var(--axis); stroke-width: 1; }
</style>
<rect class="bg" width="${WIDTH}" height="${height}" rx="8"/>
${parts.join('\n')}
</svg>
`;
  fs.writeFileSync(path.join(outDir, `${set}.svg`), svg);
  console.log(`docs/bench/${set}.svg`);
}

// The table of the README: time, CPU time, memory and the problems that match ESLint's.
const lines = [];
for (const [set, title] of Object.entries(SETS)) {
  lines.push(`**${title.replace(/^[^:]+: /, '')}**`, '', '| Project | Tool | Time | CPU time | Memory | Problems | Same as ESLint |', '|---|---|---:|---:|---:|---:|---:|');
  for (const [project, projectName] of PROJECTS) {
    for (const [tool, name] of TOOLS) {
      const r = results.results.find(x => x.set === set && x.project === project && x.tool === tool);
      if (!r) continue;
      const same = tool === 'eslint' ? '—' : `${thousands(r.matching)} of ${thousands(r.eslintProblems)}`;
      lines.push(`| ${projectName} | ${tool === 'veslint' ? '**veslint**' : name} | ${seconds(r.mean)} ± ${seconds(r.stddev ?? 0)} | ${seconds(r.cpu)} | ${thousands(r.memoryMiB)} MiB | ${thousands(r.problems)} | ${same} |`);
    }
  }
  lines.push('');
}
fs.writeFileSync(path.join(root, 'build/bench/table.md'), lines.join('\n'));
console.log('build/bench/table.md');
