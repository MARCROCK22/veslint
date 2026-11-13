import fs from 'node:fs';
import { readFile } from 'node:fs';
import * as path from 'node:path';

// Reported (TypeScript reports most of them too).
// @ts-expect-error
fs = null;
// @ts-expect-error
readFile = null;
// @ts-expect-error
path.sep = '/';
// @ts-expect-error
path.sep += '/';
// @ts-expect-error
delete path.sep;
Object.assign(path, {});
// @ts-expect-error
for (path.sep in {}) {}

// Not reported.
fs.readFileSync = null as any;
const p = path.join('a', 'b');
