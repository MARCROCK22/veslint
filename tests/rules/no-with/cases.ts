declare const obj: any;

// Reported (TypeScript reports a `with` as an error too).
with (obj) {
  toString();
}
