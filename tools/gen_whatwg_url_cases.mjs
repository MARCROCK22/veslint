// Generates tests/whatwg_url_cases.json: inputs and bases with the href Node's URL gives (null when
// it throws), and whether unicorn/relative-url-style's isSafeToAddDotSlashToUrl holds for an input
// and a base. Dev-time only: run `node tools/gen_whatwg_url_cases.mjs [urltestdata.json]` when the
// pinned Node changes; with the urltestdata.json of the web-platform-tests (url/resources/), its
// inputs and bases are added. rules/whatwg_url_test.v checks rules/whatwg_url.v against it.
import fs from 'node:fs';
import path from 'node:path';

const tryHref = (input, base) => {
  try {
    return (base === null ? new URL(input) : new URL(input, base)).href;
  } catch {
    return null;
  }
};
// isSafeToAddDotSlashToUrl of eslint-plugin-unicorn 79.0.0 (rules/relative-url-style.js).
const isSafeToAddDotSlashToUrl = (url, base) => {
  try {
    return new URL(url, base).href === new URL('./' + url, base).href;
  } catch {}
  return false;
};
// A lone surrogate does not survive JSON in V: such strings are left out (the V test checks one).
const hasLoneSurrogate = text => !text.isWellFormed();

const pairs = new Map();
const addPair = (input, base) => {
  if (hasLoneSurrogate(input) || (base !== null && hasLoneSurrogate(base))) {
    return;
  }
  pairs.set(JSON.stringify([input, base]), [input, base]);
};
const safety = new Map();
const addSafety = (url, base) => {
  if (!hasLoneSurrogate(url) && !hasLoneSurrogate(base)) {
    safety.set(JSON.stringify([url, base]), [url, base]);
  }
};

const testBases = ['https://example.com/a/b/', 'https://example.com/a/b.html', 'file:///a/b.html'];
const bases = [
  ...testBases,
  'https://example.com',
  'https://example.com/a/b/c.html',
  'https://example.com/a/b?query#hash',
  'file:///D:/project/index.js',
  'file:///C:/',
  'file:///C:',
  'file://host/share/x',
  'file://localhost/a/b',
  'file:///',
  'http://user:pw@h:8080/p/q?q#f',
  'http://h:80/',
  'mailto:x',
  'about:blank',
  'foo://h/p/q',
  'foo:/p/q',
  'foo:p',
  'foo://',
  'ftp://x/y/',
  'ws://x/',
  'wss://x:443/a',
  'http://[::1]/a/',
  'http://1.2.3.4/a',
  'blob:https://example.com/uuid',
  'data:text/plain,abc',
  'javascript:void(0)',
];

// The URLs of the rule's tests.
const ruleUrls = ['./foo', 'foo', '', '.', '..', './', '././a', '.././foo', './?query', './#section',
  '?query', '#section', '.env', '.github/workflow.yml', '..hidden/file', 'C|/asset', 'C|/image.png',
  'C:\\foo', '//example.org', 'ftp://example.org', 'https://example.org:65536', 'image.png', './file',
  '../file', '.?query', '..#section', '.\\file', '..\\file', 'https://example.com/image.png',
  '//example.com/image.png', '/image.png', 'data:image/png;base64,abc', '../image.png',
  './https://example.com/image.png', 'http:foo', 'https:foo', 'http\u003Afoo', './f\u006Fo', 'file',
  'f\u006Fo.png', '.hidden', '/', '/foo', 'small.png', 'page.html?a=1&b=2', 'a b', 'dir\nfile.png',
  '&#63;query', '?', '#', 'C|', 'C:', 'c|/', 'C:/x', '/C:/x', '//C:/x', 'file:C:/x', 'file:/C|/x',
  'file:///C|/x', 'http://example.com/a/b/', '//example.com/../../../../../x'];
for (const url of ruleUrls) {
  for (const base of bases) {
    addPair(url, base);
    addPair('./' + url, base);
    addSafety(url, base);
  }
  addPair(url, null);
}
for (const base of bases) {
  addPair(base, null);
}

// Random combinations, reproducible.
let seed = 0x5e_ed_0f;
function next() {
  seed = (Math.imul(seed, 1_103_515_245) + 12_345) >>> 0;
  return seed >>> 8;
}
const pick = list => list[next() % list.length];
const pieces = ['./', '../', '.', '..', '/', '//', '\\', '?', '#', '%', '%2e', '%2E', '%2e%2E', '.%2e',
  '%2f', '%41', '%zz', '%c3%a9', '%ff', ':', 'C:', 'c|', 'Z|', 'a', 'b', 'x.y', 'é', '€', '😀', '\u00a0',
  ' ', '\t', '\n', '\r', '\u0000', '\u001f', '\u007f', '@', ':@', 'u:p@', '[', ']', '[::1]', '[1:2::3]',
  '[::ffff:1.2.3.4]', 'http:', 'https:', 'file:', 'File:', 'HTTP:', 'ftp:', 'ws:', 'foo:', 'x+y-z.w:',
  'mailto:', '1a:', 'https://', 'http://', 'file://', 'file:///', 'foo://', '127.0.0.1', '0x7f.1',
  '1.2', '1.2.3.4.5', '256.1', '09', '0x', 'localhost', 'LOCALHOST', 'Example.COM', 'xn--a', 'xn-a',
  ':8080', ':80', ':443', ':0', ':65536', ':99999999999', ':x', '^', '`', '{', '}', '|', '"', '\'', '<',
  '>', '=', ';', ',', '$', '&', '+', '!', '~', '*', '(', ')'];
const hostPieces = ['a', 'B', '0', '1', '9', '.', '0x', '0X', 'f', 'g', '%', '%41', '%2e', '%2E', '%00',
  '%c3%a9', '%ff', 'é', 'ｅ', '-', '_', '~', 'xn--', '[', ']', ':', '::', '1.2.3.4', ' ', '\t', '^', '|',
  '<', '\u007f', '\u0001', '#', '?', '@', '/', '\\', '*', '!', '$', '&', '\'', '(', ')', '+', ',', ';',
  '=', '`', '{', '}', '"', 'localhost', '255', '256', '4294967295', '4294967296', '010', '08', '0xffffffff'];
for (let n = 0; n < 6000; n++) {
  let url = '';
  const length = 1 + (next() % 7);
  for (let i = 0; i < length; i++) {
    url += pick(pieces);
  }
  const base = pick(bases);
  addPair(url, base);
  if (n % 3 === 0) {
    addPair(url, null);
  }
  if (n % 2 === 0) {
    addSafety(url, pick(testBases));
  }
}
for (let n = 0; n < 3000; n++) {
  let host = '';
  const length = 1 + (next() % 5);
  for (let i = 0; i < length; i++) {
    host += pick(hostPieces);
  }
  addPair(pick(['http://', 'file://', 'foo://', 'ws://']) + host + pick(['', '/', '/p', ':81/', '?q', '#f']), null);
}
// IPv6 addresses.
const ipv6Pieces = ['0', '1', 'ffff', 'FFFF', '12345', 'g', ':', '::', '.', '1.2.3.4', '0.0.0.0', '256', '01',
  '1.2', ':::'];
for (let n = 0; n < 1500; n++) {
  let address = '';
  const length = 1 + (next() % 9);
  for (let i = 0; i < length; i++) {
    address += pick(ipv6Pieces);
  }
  addPair(`http://[${address}]/`, null);
}

const wpt = process.argv[2];
if (wpt) {
  for (const item of JSON.parse(fs.readFileSync(wpt, 'utf8'))) {
    if (typeof item === 'object' && item !== null && 'input' in item) {
      addPair(item.input, item.base ?? null);
      if (typeof item.base === 'string') {
        addSafety(item.input, item.base);
      }
    }
  }
}

const out = {
  node: process.version,
  ada: process.versions.ada,
  hrefs: [...pairs.values()].map(([input, base]) => [input, base, tryHref(input, base)]),
  safe: [...safety.values()].map(([url, base]) => [url, base, isSafeToAddDotSlashToUrl(url, base)]),
};
const file = path.resolve(import.meta.dirname, '../tests/whatwg_url_cases.json');
fs.writeFileSync(file, JSON.stringify(out) + '\n');
console.log(`${out.hrefs.length} hrefs (${out.hrefs.filter(item => item[2] === null).length} failures), ${out.safe.length} safety cases (${out.safe.filter(item => item[2]).length} safe), written to ${path.relative(process.cwd(), file)}`);
