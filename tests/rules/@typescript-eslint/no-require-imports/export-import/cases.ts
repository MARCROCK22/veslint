// `export import x = require('m')`: a TSImportEqualsDeclaration in an ExportNamedDeclaration (also
// with `type`, and in a module declaration). Each `require` is reported, like that of an `import`.
export import exported = require('./module');
export import type exportedType = require('./module');
export import spaced = require ('./module');
export import
  multiLine =
  require(
    './module'
  );
// @ts-expect-error: no module 'holder' to augment
declare module 'holder' {
  export import inner = require('./module');
  import local = require('./module');
  export { local };
}
/* 😀 ñ */ export import afterAstral = require('./module');
// A line break between `require` and `(` does not end it, for TypeScript.
export import lineBreak = require
  ('./module');
import lineBreakLocal = require
  ('./module');
export { lineBreakLocal };
// The alias of a name is not the import of a module, not even the alias of the name `require`.
export import alias = Names.Inner;
// @ts-expect-error: there is no namespace named `require`
export import requireAlias = require;
export namespace Names {
  export namespace Inner {
    export const value = exported.value;
  }
}
