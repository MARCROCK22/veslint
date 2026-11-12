import { AutoLoad, Command, ContextMenuCommand, Declare, EntryPointCommand, Group, Groups, GroupsT, SubCommand } from 'seyfert';
import * as Seyfert from 'seyfert';
import { AutoLoad as Load, Group as InGroup } from 'seyfert';
import { ProjectSub, RemoteCommand, RemoteSub } from './base';
import * as Base from './base';

// Valid: each decorator on its class, through any expression the superclass is.
@InGroup('admin')
class Aliased extends SubCommand {}
@Seyfert.Groups({})
class Namespaced extends Seyfert.Command {}
@Group('admin')
class FromModule extends RemoteSub {}
@AutoLoad()
class FromModuleCommand extends RemoteCommand {}
@Group('admin')
class FromNamespace extends Base.RemoteSub {}
@Group('admin')
class Reexported extends ProjectSub {}
@Group('admin')
class Parenthesized extends (SubCommand) {}
function mixin<T extends abstract new (...args: never[]) => object>(base: T) {
  return base;
}
@GroupsT({})
class Mixed extends mixin(Command) {}
declare const Constructor: abstract new () => SubCommand;
@Group('admin')
class FromConstructor extends Constructor {}
declare const Typeof: typeof Command;
@Groups({})
class FromTypeof extends Typeof {}
// @ts-expect-error: AutoLoad without a call is not a decorator of the right type
@AutoLoad
class Bare extends Command {}

// Invalid: each one is reported where it starts, with seyfert's names.
@Load()
class AliasedLoad extends SubCommand {}
@InGroup('admin') @Seyfert.GroupsT({})
class BothWrong extends ContextMenuCommand {}
@Group('admin')
class OnContextMenu extends ContextMenuCommand {}
@Groups({})
class OnEntryPoint extends EntryPointCommand {}
@AutoLoad()
class OnBaseCommand extends Seyfert.BaseCommand {}
@Group('admin')
class FromModuleWrong extends RemoteCommand {}
@GroupsT({})
class FromConstructorWrong extends Constructor {}
// @ts-expect-error: AutoLoad without a call is not a decorator of the right type
@AutoLoad
class BareWrong extends SubCommand {}
// A same-named base that is not seyfert's.
class LocalCommand {}
@Groups({})
class OnLocal extends LocalCommand {}
@Declare({ name: 'decorated', description: 'decorated' }) /* 😀 */ @Group('admin')
class AfterAstral extends Command {}
// @ts-expect-error: with experimentalDecorators, a class expression takes no decorator
const Expression = @Group('admin') class extends Command {};
// Decorators before and after `export`.
@Group('admin')
export class BeforeExport extends Command {}
export @Groups({}) class AfterExport extends SubCommand {}
function inside() {
  @AutoLoad()
  class Nested extends SubCommand {}
  return Nested;
}

export { Aliased, AliasedLoad, AfterAstral, Bare, BareWrong, BothWrong, Expression, FromConstructor, FromConstructorWrong };
export { FromModule, FromModuleCommand, FromModuleWrong, FromNamespace, FromTypeof, inside, Mixed, Namespaced, OnBaseCommand };
export { OnContextMenu, OnEntryPoint, OnLocal, Parenthesized, Reexported };
