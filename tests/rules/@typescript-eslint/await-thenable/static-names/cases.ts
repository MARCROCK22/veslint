// The method name is read with getStaticMemberAccessValue: any static value, not only a literal.
const allKey = 'all';
async function names() {
  await Promise[allKey]([1, 2]);
  await Promise['ra' + 'ce']([1, 2]);
  await Promise[`any`]([1, 2]);
  await Promise['\x61llSettled']([1, 2]);
  await Promise['resolve']([1, 2]);
}
export { names };
