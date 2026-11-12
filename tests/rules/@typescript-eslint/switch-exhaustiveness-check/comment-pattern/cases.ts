// defaultCaseCommentPattern: the last comment after the last case counts as the default when its
// trimmed text matches the pattern (no longer `no default`).
declare const n: number;
declare const u: 'a' | 'b';
function f() {
  switch (n) {
    case 1:
      break;
    // skip default
  }
  switch (n) {
    case 1:
      break;
    // Skip default
  }
  switch (n) {
    case 1:
      break;
    // skip default: nothing else to do
  }
  switch (n) {
    case 1:
      break;
    // no default
  }
  switch (n) {
    case 1:
      break;
    /*   skip default   */
  }
  switch (n) {
    case 1:
      break;
    // skipdefault
  }
  switch (n) {
    case 1:
      break;
    // please skip default
  }
  switch (u) {
    case 'a':
      break;
    // skip	default
  }
  switch (u) {
    case 'a':
      break;
    // no default
  }
  switch (n) {
    case 1:
      break;
    // skip default
    // another comment
  }
}
export { f };
