import { AutoLoad, Command, Declare, Group, Groups, GroupsT, Options, SubCommand } from 'seyfert';
import * as Seyfert from 'seyfert';
import { AliasSub, Ban, Dynamic, Expression, modGroup, sharedGroups, System, Templated, Typo, Ungrouped } from './groups';

@Declare({ name: 'local', description: 'local' })
@Group('mod')
class LocalBan extends SubCommand {}
@Declare({ name: 'local-typo', description: 'local typo' })
@Group('mdo')
class LocalTypo extends SubCommand {}

// Reported at the subcommand of an array written in the decorator, or at the argument otherwise.
@Declare({ name: 'inline', description: 'inline' })
@Groups({ mod: { defaultDescription: 'Moderation' } })
@Options([Ban, Typo, LocalBan, LocalTypo, Templated, System])
class Inline extends Command {}
const subs = [Ban, Typo, LocalTypo];
@Declare({ name: 'variable', description: 'variable' })
@Groups({ mod: modGroup })
@Options(subs)
class Variable extends Command {}

// Groups read through a `const`, an import, defineGroups, a spread, a shorthand, aliases and keys.
@Declare({ name: 'shared', description: 'shared' })
@Groups(sharedGroups)
@Options([Ban, System, AliasSub, Typo, Templated])
class Shared extends Command {}
const mod = { defaultDescription: 'Moderation' };
const templatedAliases = ['templated'];
@Declare({ name: 'spread', description: 'spread' })
@Seyfert.GroupsT({ ...sharedGroups, mod, ['typo']: { defaultDescription: 'Typo', aliases: templatedAliases } })
@Options([Ban, Typo, Templated, LocalTypo])
class Spread extends Command {}

// The groups of the classes it extends count too; no @Groups at all declares none.
@Groups({ mod: { defaultDescription: 'Moderation' } })
class ModBase extends Command {}
@Declare({ name: 'inherited', description: 'inherited' })
@Options([Ban, Typo])
class Inherited extends ModBase {}
@Declare({ name: 'none', description: 'none' })
@Options([Ban])
class None extends Command {}

// Not checked: groups that cannot be read, a `groups` member, not a command, no group to check.
@Declare({ name: 'unreadable', description: 'unreadable' })
@Groups({ mod: { defaultDescription: 'Moderation', aliases: [String(1)] } })
@Options([Typo])
class Unreadable extends Command {}
// A shorthand `aliases` is looked up as the property, not as the `const` it names: unreadable.
const aliases = ['typo'];
@Declare({ name: 'shorthand-aliases', description: 'shorthand aliases' })
@Groups({ mod: { defaultDescription: 'Moderation', aliases } })
@Options([Typo])
class ShorthandAliases extends Command {}
@Declare({ name: 'method', description: 'method' })
// @ts-expect-error: a group is not a method
@Groups({ mod() {} })
@Options([Typo])
class Method extends Command {}
@Declare({ name: 'member', description: 'member' })
@Groups({ mod: { defaultDescription: 'Moderation' } })
@Options([Typo])
class Member extends Command {
  groups = {};
}
@Declare({ name: 'sub', description: 'sub' })
@Options([Typo])
class NotCommand extends SubCommand {}
@Declare({ name: 'unknown-groups', description: 'unknown groups' })
@Groups({ mod: { defaultDescription: 'Moderation' } })
@Options([Dynamic, Ungrouped, Expression, ...[Typo]])
class NothingToCheck extends Command {}

// @AutoLoad reads the default exports of the modules of the program in this directory.
@Declare({ name: 'loaded', description: 'loaded' })
@AutoLoad()
@Groups({ mod: { defaultDescription: 'Moderation' } })
class Loaded extends Command {}

export { Inherited, Inline, Loaded, Member, Method, None, NotCommand, NothingToCheck, Shared, ShorthandAliases, Spread };
export { Unreadable, Variable };
