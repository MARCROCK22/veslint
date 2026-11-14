import {newImported} from './other';
declare const object: {newProperty: number; plain: number};

// Bindings are still reported.
const newFoo = 1;
function newFunction(newParameter: number, newDefault = 1) {}
const {newRenamed: plain} = object as unknown as {newRenamed: number};
const {plain: newBinding} = object as unknown as {plain: number};
const {newShorthand} = object as unknown as {newShorthand: number};
const {newShorthandDefault = 1} = object as unknown as {newShorthandDefault?: number};

// Properties are not.
object.newProperty = 1;
newFoo.toString();
const objectLiteral = {newKey: 1, newFoo};
type Alias = {newMember: number};
export {newImported, newBinding, newShorthand, newShorthandDefault, objectLiteral};
