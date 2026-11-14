// unicorn/prefer-export-from: re-export with `export…from` instead of import + export.
import defaultValue from 'default-module';
export default defaultValue;

import {named} from 'named-module';
export {named};

import {original as renamed} from 'renamed-module';
export {renamed as original};

import {first, second} from 'pair-module';
export {first, second as other};

import * as everything from 'namespace-module';
export {everything};

import * as namespaceDefault from 'namespace-default-module';
export default namespaceDefault;

import {"string name" as stringName} from 'string-module';
export {stringName as "string name"};

import {plain} from 'plain-module';
export {plain as "plain"};

import {reused} from 'reused-module';
export {existing} from 'reused-module';
export {reused};

import {empty} from 'empty-module';
export {} from 'empty-module';
export {empty};

import data from './data.json' with {type: 'json'};
export {data};

import {constant} from 'constant-module';
export const alias = constant;

import {typed} from 'typed-const-module';
export const typedAlias: unknown = typed;

import {used} from 'used-module';
export {used as usedToo};
console.log(used);

import {many} from 'many-module';
export {many as manyOne};
export {many as manyTwo};

import {documented} from 'documented-module';
/** Documented re-export. */
export const documentedAlias = documented;

import {plainComment} from 'plain-comment-module';
/* Not a JSDoc comment. */
export const plainCommentAlias = plainComment;

import {commented} from 'commented-module'; // a trailing comment is outside
export {commented /* inside */};

import /* inside */ {commentedImport} from 'commented-import-module';
export {commentedImport};

import type {OnlyType} from 'type-module';
export type {OnlyType};

import type {TypeA} from 'type-reuse-module';
export type {TypeB} from 'type-reuse-module';
export type {TypeA};

import {type InlineType} from 'inline-type-module';
export {InlineType};

import {ValueAsType} from 'value-as-type-module';
export type {ValueAsType};

import {ValueReuse} from 'value-reuse-module';
export {other as otherValue} from 'value-reuse-module';
export {type ValueReuse};

import type * as TypeNamespace from 'type-namespace-module';
export type {TypeNamespace};

import type TypeDefault from 'type-default-module';
export {TypeDefault};

import mixedDefault, {mixedNamed} from 'mixed-module';
export {mixedDefault, mixedNamed};

import combinedDefault, * as combinedNamespace from 'combined-module';
export {combinedDefault as combined, combinedNamespace};

import {notExported} from 'not-exported-module';
const local = notExported;
export {local};

import {destructured} from 'destructured-module';
export const {property} = {property: destructured};

import {letValue} from 'let-module';
export let letAlias = letValue;

import {parenthesized} from 'parenthesized-module';
export default (parenthesized);

declare module 'ambient' {
	import {inner} from 'inner-module';
	export {inner};
}

import 'side-effect-module';
import {} from 'nothing-module';
