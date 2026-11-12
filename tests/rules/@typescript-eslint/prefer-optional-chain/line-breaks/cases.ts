// The report starts where the chain does: its line and its column are counted with a lone CR,
// U+2028, U+2029 and CRLF as line breaks (see no-floating-promises/line-breaks).
declare const foo: { bar?: { baz?: number } } | undefined;
void (foo && foo.bar);void (foo && foo.bar); void (foo && foo.bar); void (foo && foo.bar);
void (foo && foo.bar);
void (foo &&  foo.bar &&   foo.bar.baz); /* 😀 */ void (foo != null && foo.bar);
if (   (foo && foo.bar)) { }
