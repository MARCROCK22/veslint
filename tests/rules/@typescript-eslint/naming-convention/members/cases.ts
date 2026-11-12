// naming-convention: the names of everything.
import DefaultImport from './module';
import default_import from './module';
import * as Namespace from './module';
import * as name_space from './module';
import { default as RenamedDefault, named_import, NamedImport as local_name } from './module';
void local_name;
import { default as renamed_default } from './module';

const camelCase = 1;
const PascalCase = 2;
const snake_case = 3;
const UPPER_CASE = 4;
const _leading = 5;
const trailing_ = 6;
const __double = 7;
const double__ = 8;
const mixed_Case = 9;
const HTMLParser = 10;
const strictHTMLParser = 11;
let letVariable = 1;
let Let_Variable = 2;
var varVariable = 3;
export const exported_const = 1;
export const ExportedConst = 2;
export let exportedLet = 3;
const later_exported = 1;
export { later_exported, camelCase as Renamed };
export default PascalCase;
const isReady = true;
const ready = false;
const hasItems: boolean = true;
const maybeFlag: boolean | undefined = undefined;
const items = [1, 2];
const item = [1, 2];
const nameList: string[] = [];
const tuple: [number, string] = [1, 'a'];
const onClick = () => {};
const click = function () {};
const handleSubmit = async () => {};
const doWork = async function () {};
const work = async () => {};
const text = 'text';
const TEXT_VALUE = 'text';
const Count = 1;
const { destructured_name, other: renamed_other, nested: { deep_name }, ...rest_object } = { destructured_name: 1, other: 2, nested: { deep_name: 3 }, x: 4 };
const [first_element, , third = 3, ...rest_elements] = [1, 2];
const { defaulted_name = 1 } = {} as { defaulted_name?: number };
for (const loop_variable of items) {
  void loop_variable;
}
for (let index_variable = 0; index_variable < 1; index_variable++) {}
for (const key_name in { a: 1 }) {
  void key_name;
}

function camelFunction() {}
function PascalFunction() {}
function snake_function() {}
function _privateFunction() {}
function LegacyFunction() {}
async function fetchData() {}
async function fetchDataAsync() {}
export function exportedFunction() {}
export function Exported_Function() {}
export async function exportedAsync() {}
declare function declared_function(first_param: string): void;
function* generatorFunction() {}
const named_expression = function inner_name() {};
function parameters(camelParam: string, PascalParam: number, snake_param: boolean, _unused: unknown, __double: unknown, trailing_: unknown, isEnabled: boolean, enabled: boolean, { destructured_param, renamed: renamed_param }: { destructured_param: number; renamed: number }, [array_param]: number[], defaulted_param = 1, ...rest_params: number[]) {
  function nested_function(inner_param: string) {}
  const local_variable = 1;
  return [nested_function, local_variable];
}
const arrow = (arrow_param: string, UpperParam: number) => arrow_param;
const single = single_param => single_param;
function withThis(this: Window, value_param: string) {}

class camelClass {}
class PascalClass {}
class snake_class {}
abstract class AbstractShape {}
abstract class Shape {}
export class UserService {}
export class UserThing {}
export default class DefaultClass {}
const ClassExpression = class inner_class {};

class Members {
  camelProperty = 1;
  PascalProperty = 2;
  snake_property = 3;
  _underscored = 4;
  __doubleUnderscored = 5;
  private privateProperty = 6;
  private _privateUnderscored = 7;
  protected protectedProperty = 8;
  public publicProperty = 9;
  readonly readonlyProperty = 10;
  static staticProperty = 11;
  static readonly STATIC_READONLY = 12;
  static readonly staticReadonly = 13;
  #hashProperty = 14;
  #hash_property = 15;
  declare declaredProperty: number;
  optionalProperty?: string;
  isActive = true;
  active = false;
  'quoted-property' = 1;
  'quotedProperty' = 2;
  123 = 3;
  ['computed_property'] = 4;
  arrowMethod = () => {};
  Arrow_Method = () => {};
  functionProperty = function () {};
  asyncArrow = async () => {};
  asyncArrowAsync = async () => {};
  accessor autoAccessor = 1;
  accessor auto_accessor = 2;
  static accessor StaticAccessor = 3;

  constructor(
    private paramProperty: string,
    private readonly READONLY_PARAM: string,
    public readonly readonlyParam: string,
    protected Param_Property: string,
    public listParam: string[],
    public list_param: string[],
    plainParam: string,
    Plain_Param: string,
  ) {}
  camelMethod() {}
  PascalMethod() {}
  snake_method() {}
  _underscoredMethod_() {}
  HTMLMethod() {}
  private privateMethod() {}
  private _privateMethod() {}
  static staticMethod() {}
  async asyncMethod() {}
  async asyncMethodAsync() {}
  *generatorMethod() {}
  #hashMethod() {}
  #hash_method() {}
  'quoted-method'() {}
  ['computed_method']() {}
  get getterName() {
    return 1;
  }
  set getterName(value_param: number) {}
  get GetterName() {
    return 1;
  }
  get COUNT_VALUE(): number {
    return 1;
  }
  static get staticGetter() {
    return 1;
  }
  overloaded(first_overload: string): void;
  overloaded(second_overload: number): void;
  overloaded(implementation_param: unknown) {}
}
abstract class AbstractMembers {
  abstract abstractProperty: number;
  abstract AbstractProperty: number;
  abstract abstractMethod(): void;
  abstract AbstractMethod(abstract_param: string): void;
  abstract get abstractGetter(): number;
}
class Overrides extends Members {
  override camelProperty = 1;
  override snake_property = 2;
  override camelMethod() {}
}

const objectLiteral = {
  camelKey: 1,
  PascalKey: 2,
  snake_key: 3,
  _underscoredKey: 4,
  'quoted-key': 5,
  'quoted_key': 6,
  'QUOTED KEY': 7,
  123: 8,
  ['computed_key']: 9,
  isFlag: true,
  flag: false,
  camelCase,
  snake_case,
  methodKey() {},
  Method_Key() {},
  async asyncKey() {},
  arrowKey: () => {},
  Arrow_Key: () => {},
  functionKey: function () {},
  asyncArrowKey: async () => {},
  get getterKey() {
    return 1;
  },
  set getterKey(setter_param: number) {},
  get Getter_Key() {
    return 1;
  },
  ...{ spread_key: 1 },
};

interface camelInterface {}
interface PascalInterface {}
interface IPrefixed {}
interface snake_interface {}
export interface Exported_Interface {}
interface TypeMembers<TKey, Value, snake_param> {
  camelProperty: string;
  PascalProperty: number;
  snake_property: boolean;
  readonly readonlyProperty: string;
  readonly READONLY_PROPERTY: string;
  'quoted-property': number;
  isValid: boolean;
  valid: boolean;
  camelMethod(): void;
  PascalMethod(method_param: string): void;
  snake_method(): void;
  functionProperty: () => void;
  Function_Property: (callback_param: string) => void;
  parenthesized: (() => void);
  optionalMethod?(): void;
  get accessorProperty(): number;
  [index: string]: unknown;
  ['computed_property']: number;
}
type camelAlias = string;
type PascalAlias = number;
type AliasType = boolean;
type snake_alias = { inner_property: string; innerMethod(): void };
export type Exported_Alias = string;
type Generic<T, TValue, lower, K extends string = string> = [T, TValue, lower, K];
type Inferred<T> = T extends Array<infer inferred_type> ? inferred_type : never;
type Mapped<T> = { [mapped_key in keyof T]: T[mapped_key] };
type FunctionType = (function_type_param: string) => void;
function genericFunction<T, TResult, lower_case>(value: T): TResult | lower_case {
  return value as unknown as TResult;
}

enum camelEnum {
  camelMember,
  PascalMember,
  UPPER_MEMBER,
  snake_member,
  'quoted-member' = 4,
  'QuotedMember' = 5,
  MEMBER__ = 6,
}
enum PascalEnum {}
export enum Exported_Enum {
  A,
}
export enum EXPORTED_ENUM {
  B,
}
const enum ConstEnum {
  C,
}
declare enum DeclaredEnum {
  D,
}
namespace NamespaceName {
  export const namespace_variable = 1;
  export function Namespace_Function() {}
}
try {
} catch (catch_error) {}
label_name: for (;;) {
  break label_name;
}
void [DefaultImport, default_import, Namespace, name_space, RenamedDefault, named_import, renamed_default];
