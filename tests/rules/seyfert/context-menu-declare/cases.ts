import { ApplicationCommandType, Command, ContextMenuCommand, Declare, Middlewares } from 'seyfert';
import * as Seyfert from 'seyfert';
import { Declare as D } from 'seyfert';
import { nested, remoteWithDescription, remoteWithoutType } from './options';
import * as Remote from './options';

// Valid: a type and no description.
@Declare({ name: 'user', type: ApplicationCommandType.User })
class UserMenu extends ContextMenuCommand {}
const type = ApplicationCommandType.Message;
@D({ name: 'message', type })
class Shorthand extends ContextMenuCommand {}
const base = { type: ApplicationCommandType.User };
@Declare({ ...base, name: 'spread' })
class Spread extends ContextMenuCommand {}
@Declare({ name: 'string key', 'type': ApplicationCommandType.User, ['description']() {} })
class DescriptionMethod extends ContextMenuCommand {}

// Reported: no type (at the decorator), or a description (at its property).
@Declare({ name: 'untyped' })
class Untyped extends ContextMenuCommand {}
@Seyfert.Declare({
  name: 'described',
  type: ApplicationCommandType.User,
  description: 'not for a context menu',
})
class Described extends ContextMenuCommand {}
const description = 'shorthand';
@Declare({ name: 'both', description })
class Both extends ContextMenuCommand {}
@Declare({ name: 'keys', type: 2, 'description': 'a', ['description']: 'b', [`description`]: 'c' })
class Keys extends ContextMenuCommand {}
@Declare({ ...base, name: 'spread', description: 'with a spread' })
class SpreadWithDescription extends ContextMenuCommand {}
@Declare({ name: 'method', type() { return 2; } })
class TypeMethod extends ContextMenuCommand {}
@Declare(({ name: 'wrapped', description: 'wrapped' }) as const)
class Wrapped extends ContextMenuCommand {}
/* 😀 */ @Declare({ name: 'astral', /* ñ */ description: 'astral' }) class Astral extends ContextMenuCommand {}

// Through a `const` of this file: a description is reported where it is written.
const local = {
  name: 'local',
  description: 'local',
};
const alias = local;
@Declare(alias satisfies object)
class Local extends ContextMenuCommand {}

// Through another module: what is written there is reported at the decorator.
@Declare(remoteWithDescription)
class RemoteDescribed extends ContextMenuCommand {}
@Declare(remoteWithoutType)
class RemoteUntyped extends ContextMenuCommand {}
@Declare(Remote.remoteWithoutType)
class RemoteNamespace extends ContextMenuCommand {}

// Not resolved: a `let`, a property of an object, a spread, no argument, no call.
let changing = { name: 'changing' };
@Declare(changing)
class Changing extends ContextMenuCommand {}
@Declare(nested.menu)
class Nested extends ContextMenuCommand {}
const args = [{ name: 'args' }] as const;
// @ts-expect-error: a spread argument for a parameter that is not a rest one
@Declare(...args)
class SpreadArgument extends ContextMenuCommand {}
// @ts-expect-error: Declare needs its options
@Declare()
class NoArgument extends ContextMenuCommand {}
// @ts-expect-error: Declare without a call is not a decorator of the right type
@Declare
class NoCall extends ContextMenuCommand {}

// Only the first @Declare counts, and only on a context menu command.
@Middlewares([])
@Declare({ name: 'first', type: 2 })
@Declare({ name: 'second', description: 'second' })
class Twice extends ContextMenuCommand {}
@Declare({ name: 'chat', description: 'chat' })
class Chat extends Command {}
abstract class MenuBase extends ContextMenuCommand {}
@Declare({ name: 'inherited', description: 'inherited' })
class Inherited extends MenuBase {}
// @ts-expect-error: with experimentalDecorators, a class expression takes no decorator
const Expression = @Declare({ name: 'expression' }) class extends ContextMenuCommand {};

export { Astral, Both, Changing, Chat, Described, DescriptionMethod, Expression, Inherited, Keys, Local, Nested, NoArgument };
export { NoCall, RemoteDescribed, RemoteNamespace, RemoteUntyped, Shorthand, Spread, SpreadArgument, SpreadWithDescription };
export { Twice, TypeMethod, Untyped, UserMenu, Wrapped };
