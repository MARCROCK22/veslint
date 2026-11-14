declare const base: string;
declare const name: string;

// Reported, with a fix.
new URL('foo', base);
new URL("foo", base);
new URL(`file`, base);
new URL('f\u006Fo', base);
new URL('.env', base);
new URL('.github/workflow.yml', base);
new URL('..hidden/file', base);
new URL('\u002Eenv', base);
new URL('', 'https://example.com/a/b/');
new URL(``, 'https://example.com/a/b/');
new URL('?query', 'https://example.com/a/b/');
new URL('C|/asset', 'https://example.com/a/b.html');
new URL('image.png', 'file:///D:/project/index.js');
new URL('foo' as string, base);
new URL(<string>'foo', base);
new URL('ünïcode/😀.png', base);
URL.canParse('image.png', base);
URL.parse(`image.png`, base);

// Not reported.
new URL('./foo', base);
new URL('', base);
new URL('.', base);
new URL('..', base);
new URL('../foo', base);
new URL('.?query', base);
new URL('..#section', base);
new URL('.\\file', base);
new URL('/', base);
new URL('/foo', base);
new URL('?query', base);
new URL('#section', base);
new URL('C:\\foo', base);
new URL('C|/asset', base);
new URL('//example.org', 'https://example.com');
new URL('ftp://example.org', 'https://example.com');
new URL('https://example.org:65536', 'https://example.com');
new URL('http:foo', base);
new URL(`${name}`, base);
new URL(`./${name}`, base);
new URL('foo' satisfies string, base);
new URL('', 'https://example.com/a/b.html');
URL.canParse('image.png');
