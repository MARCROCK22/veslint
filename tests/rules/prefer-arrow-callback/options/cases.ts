declare function use(...f: unknown[]): void;

// Reported with allowUnboundThis false.
use(function () {
  return this;
});

// Not reported with allowNamedFunctions.
use(function named() {});
