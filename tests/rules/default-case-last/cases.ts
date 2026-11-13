declare const x: number;

// Reported.
switch (x) {
  default:
    break;
  case 1:
    break;
}
switch (x) {
  case 1:
  default:
  case 2:
}
switch (x) {
  // comment
  default: {
  }
  case 3:
}

// Not reported.
switch (x) {
  case 1:
    break;
  default:
}
switch (x) {
  case 1:
}
switch (x) {
  default:
  // comment after
}
switch (x) {}
