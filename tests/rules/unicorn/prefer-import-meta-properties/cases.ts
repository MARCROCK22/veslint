import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as url from 'url';
import { dirname } from 'path';

const filename = fileURLToPath(import.meta.url);
const dir = path.dirname(filename);
const dir2 = dirname(fileURLToPath(import.meta.url));
const file2 = url.fileURLToPath(new URL(import.meta.url));
const dir3 = fileURLToPath(new URL('.', import.meta.url));
const dir4 = url.fileURLToPath(new URL('./', import.meta.url));
const dir5 = path.dirname(import.meta.filename);
const file3 = fileURLToPath(/* c */ import.meta.url);
const { fileURLToPath: toPath } = process.getBuiltinModule('node:url');
const file4 = toPath(import.meta.url);
const k1 = fileURLToPath(new URL('../', import.meta.url));
const k2 = path.join(filename, 'x');
export { dir, dir2, file2, dir3, dir4, dir5, file3, file4, k1, k2 };
