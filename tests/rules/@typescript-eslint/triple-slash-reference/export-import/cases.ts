/// <reference types="exported" />
/// <reference types="inner" />
// `export import x = require('m')`: a TSImportEqualsDeclaration with an external module, in an
// ExportNamedDeclaration.
export import exported = require('exported');
declare module 'holder' {
  export import inner = require('inner');
}
export import alias = exported.x;
