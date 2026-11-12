// The method name is read with getStaticMemberAccessValue: any static value, not only a literal.
declare const list: number[];
declare const p: Promise<number>;
const filterKey = 'filter';
const finallyKey = 'finally';
list[filterKey](async () => true);
list['so' + 'me'](async () => true);
list[`every`](async () => true);
list['\x66ind'](async () => true);
list['map'](async () => true);
void p[finallyKey](async () => {});
void p['fin' + 'ally'](async () => {});
