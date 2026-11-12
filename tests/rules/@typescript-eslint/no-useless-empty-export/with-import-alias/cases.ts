// An import-equals declaration of a namespace counts as another export.
namespace A { export const b = 1; }
import B = A.b;
export {};
void B;
