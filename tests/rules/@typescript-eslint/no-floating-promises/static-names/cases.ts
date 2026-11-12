// The method name is read with getStaticMemberAccessValue: any static value, not only a literal.
declare const p: Promise<number>;
const catchKey = 'catch';
const thenKey = 'then';
const finallyKey = 'finally';
const notConst = Math.random() > 0.5 ? 'catch' : 'then';
async function names() {
  p[catchKey](() => {});
  p['ca' + 'tch'](() => {});
  p[`${'cat'}ch`](() => {});
  p['\x63atch'](() => {});
  p[thenKey](() => {}, () => {});
  p[thenKey](() => {});
  p[finallyKey](() => {});
  p[catchKey](() => {})[finallyKey](() => {});
  p[notConst](() => {});
  p[catchKey](null);
  p[['catch'] as never](() => {});
}
export { names };
