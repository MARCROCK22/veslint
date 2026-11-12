import { Command, ContextMenuCommand, Declare, EntryPointCommand, Options, SubCommand } from 'seyfert';
import * as Seyfert from 'seyfert';
import { Declare as D } from 'seyfert';
import { AmbientBase } from './ambient';
import { DeclaredBase, ProjectCommand, UndeclaredBase, UndeclaredSub } from './base';

// Reported at the name of the class, or at the class when it has none.
class Missing extends Command {}
class MissingSub extends SubCommand {}
class MissingMenu extends ContextMenuCommand {}
class MissingEntry extends EntryPointCommand {}
@Options({})
class OptionsOnly extends Command {}
class FromReexport extends ProjectCommand {}
class FromNamespace extends Seyfert.Command {}
// A base of the project without @Declare: the class has to declare itself.
abstract class LocalAbstract extends Command {}
class FromLocalAbstract extends LocalAbstract {}
class FromUndeclared extends UndeclaredBase {}
class FromUndeclaredSub extends UndeclaredSub {}
const Named = class NamedExpression extends Command {};
const Anonymous = class extends Command {};
// @ts-expect-error: with experimentalDecorators, a class expression takes no decorator
const DecoratedAnonymous = @Options({}) class extends Command {};
function inside() {
  return class extends SubCommand {};
}
/* 😀 ñ */ class AfterAstral extends Command {}
class
  MultiLine
  extends Command {}
@Options({}) export class DecoratedExport extends Command {}
export @Options({}) class ExportDecorated extends Command {}
class Implementing extends Command implements Disposable {
  [Symbol.dispose]() {}
}

// Valid: declared, abstract, ambient, or a base that has or may have @Declare.
@Declare({ name: 'declared', description: 'declared' })
class Declared extends Command {}
@D({ name: 'aliased', description: 'aliased' })
class Aliased extends Command {}
@Seyfert.Declare({ name: 'namespaced', description: 'namespaced' })
class Namespaced extends Command {}
abstract class Abstract extends Command {}
declare class Ambient extends Command {}
class FromDeclared extends DeclaredBase {}
class FromDeclaredLocal extends Declared {}
class Grandchild extends FromDeclared {}
class FromAmbient extends AmbientBase {}
function mixin<T extends abstract new (...args: never[]) => object>(base: T) {
  return base;
}
class Mixed extends mixin(Command) {}
// TypeScript's expression of the heritage clause is the parenthesized one, which has no symbol.
class Parenthesized extends (Command) {}
class NotACommand {}
class Plain extends NotACommand {}
class NoBase implements Disposable {
  [Symbol.dispose]() {}
}

export { Abstract, Aliased, Ambient, Anonymous, AfterAstral, Declared, DecoratedAnonymous, FromAmbient, FromDeclared };
export { FromDeclaredLocal, FromLocalAbstract, FromNamespace, FromReexport, FromUndeclared, FromUndeclaredSub, Grandchild };
export { Implementing, inside, Missing, MissingEntry, MissingMenu, MissingSub, Mixed, MultiLine, Named, Namespaced, NoBase };
export { OptionsOnly, Parenthesized, Plain };
