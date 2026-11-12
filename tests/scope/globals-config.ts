/* global fromBoth: off, onlyComment, __proto__: writable, 5: writable */
/* globals fromBoth: writable, valueLess:, */
/* exported onlyComment, 'quoted', "double", unknownName, fromConfig */
// languageOptions.globals with every kind of value, in the order of the configuration.
// global lineComment
// exported fromBoth
lineComment;
fromConfig; fromBoth; onlyComment; valueLess; quoted; double;
const cls = [class fromConfig {}, class onlyComment {}, class nothing {}, class quoted {}];
export { cls };
