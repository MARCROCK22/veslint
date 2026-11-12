// The `package` of a type specifier is a regular expression for typescript-eslint, which makes one
// of the name as it is and looks for it in the name TypeScript gives each file of a package.
import {
  anchoredTask, anchoredWrongTask, eitherTask, emptyTask, literalBraceTask, lookTask, unitTask,
} from 'fake-pkg';
import { backTask, braceTask, classTask, otherEitherTask } from 'other-pkg';
import { escapedPlusTask, plusTask } from 'x+y';
import { scopedDotTask, scopedTypesTask } from '@scope/pkg';

async function promises() {
  // `^fake-pkg/` is at the start of `fake-pkg/index.d.ts`, and `^ake-pkg` is not.
  anchoredTask();
  anchoredWrongTask();
  // An alternative, a lookahead, the empty name (which is in every name) and a `{` that is not a
  // quantifier.
  eitherTask();
  otherEitherTask();
  lookTask();
  emptyTask();
  literalBraceTask();
  // A quantifier in braces, a class, groups with a hexadecimal escape.
  unitTask();
  classTask();
  braceTask();
  backTask();
  // The package `x+y` is not in the pattern `x+y`, and it is in `x\+y`.
  plusTask();
  escapedPlusTask();
  // `.` is any character, and the case counts.
  scopedDotTask();
  scopedTypesTask();
}
export { promises };
