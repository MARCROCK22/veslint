// switch-exhaustiveness-check: defaultCaseCommentPattern with modifiers and Unicode properties.
declare const n: number;
switch (n) {
  case 1:
    break;
  // SKIP défaut
}
switch (n) {
  case 1:
    break;
  // Skip 123
}
switch (n) {
  case 1:
    break;
  /* ſKIP default
     on two lines */
}
switch (n) {
  case 1:
    break;
  // skip
}
switch (n) {
  case 1:
    break;
  // sKiP ΩMEGA: reason
}
