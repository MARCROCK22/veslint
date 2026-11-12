// An exported import-equals declaration counts.
namespace A { export const b = 1; }
export import B = A.b;
export {};
