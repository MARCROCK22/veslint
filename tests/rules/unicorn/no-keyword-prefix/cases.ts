import {newImported} from './other';
import {original as newRenamed, newOriginal as plain} from './other';
import newDefault from './other';
import * as newNamespace from './other';
import type {newType} from './other';
declare function fn(...values: unknown[]): unknown;
declare const object: {newProperty: number; classProperty: number; plain: number};
declare const value: number;

// Variables, functions and classes.
const newFoo = 1;
let classBar: number = 2;
var newBaz;
function newFunction(newParameter: number, newDefaultParameter = 1, ...newRest: number[]) {}
const newArrow = (newArrowParameter: string) => newArrowParameter;
class newClass {
	newField = 1;
	#newPrivate = 2;
	static newStatic = 3;
	newMethod() {
		return this.#newPrivate;
	}
	get newGetter() {
		return 1;
	}
	constructor(private newParameterProperty: number) {}
}
const classExpression = class newClassExpression {};
label: for (const newLoop of [1]) {}
try {} catch (newError) {}

// Not reported: other names.
const fooNew = 1;
const NEW_FOO = 1;
const _newFoo = 1;
const new_foo = 1;
const newfoo = 1;
const news = 1;
const classic = 1;
const $newFoo = 1;
const newÉtoile = 1;
const new1 = 1;

// Types.
type newAlias = {newMember: string; classMember(): void};
interface newInterface {
	newSignature: number;
	newMethodSignature(newSignatureParameter: string): void;
}
enum newEnum {
	newEnumMember,
}
declare namespace newNamespaceDeclaration {
	const newInNamespace: number;
}
function generic<newTypeParameter>(parameter: newTypeParameter): newAlias | undefined {
	return undefined;
}
let typed: newInterface | newType;

// Calls and constructions.
newFunction(1);
new newClass(1);
fn(newFoo, classBar);
fn(newFoo.toString());
new newClass(newFoo);

// Member expressions.
newFoo.toString();
object.newProperty;
object.newProperty = 1;
object.newProperty = object.plain;
object.plain = object.newProperty;
object.classProperty += value;
object[newFoo];
newBaz = 1;
newBaz = object.newProperty;
const fromMember = newNamespace.newMember;
newNamespace.newNamespace;

// Objects and destructuring.
const objectLiteral = {newKey: 1, classKey() {}, newFoo, [newFoo]: 2, plain: newFoo};
const {newDestructured} = object as unknown as {newDestructured: number};
const {newRenamedKey: plainBinding} = object as unknown as {newRenamedKey: number};
const {plainKey: newBinding} = object as unknown as {plainKey: number};
const {newWithDefault = 1} = object as unknown as {newWithDefault?: number};
const {plainDefault = newFoo} = object as unknown as {plainDefault?: number};
const {[newFoo]: computedBinding} = object as unknown as {[key: number]: number};
const {nested: {newNested}} = object as unknown as {nested: {newNested: number}};
const [newArrayElement, classArrayElement = 1] = [1, 2];
function destructuredParameter({newParameterKey, plain: newRenamedParameter}: {newParameterKey: number; plain: number}) {}

// Exports.
export {newFoo, newFoo as exportedPlain, plain as newExported};
export {newOriginal as newReexported} from './other';
export default newArrow;
export const newExportedConst = 1;
