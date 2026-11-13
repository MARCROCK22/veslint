declare function use(f: unknown): void;

// Reported with "never", but generators "always".
use(function named() {});
const a = function b() {};
use(function* () {});

// Not reported.
use(function () {});
use(function* gen() {});
use(function recursive(): unknown {
  return recursive;
});
function decl() {}
export default function exported() {}
