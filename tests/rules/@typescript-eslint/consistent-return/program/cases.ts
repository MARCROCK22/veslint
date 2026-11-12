// consistent-return at the top level of a file.
declare const flag: boolean;
if (flag) {
  return 1;
}
if (!flag) {
  return;
}
