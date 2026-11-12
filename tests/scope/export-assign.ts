// TSExportAssignment and TSNamespaceExportDeclaration.
const thing = { a: 1 };
type thing = number;
namespace ns { export const x = thing; }
export = thing;
export as namespace Umd;
