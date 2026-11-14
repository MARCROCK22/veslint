declare function use(...f: unknown[]): void;

// Without ecmaFeatures.jsx in the parser options, no `,` after a lone type parameter (10.15.0).
use(function <T,>(x: T) { return x; });
use(function <T extends unknown>(x: T) { return x; });
use(function <T, U>(x: T, y: U) { return [x, y]; });
