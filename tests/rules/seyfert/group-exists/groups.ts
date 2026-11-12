// Groups and subcommands of other modules of the project.
import { Declare, defineGroups, Group, SubCommand } from 'seyfert';

export const sharedGroups = defineGroups({
  mod: { defaultDescription: 'Moderation' },
  sys: { defaultDescription: 'System', aliases: ['system'] },
});
export const modGroup = { defaultDescription: 'Moderation' };

@Declare({ name: 'ban', description: 'ban' })
@Group('mod')
export class Ban extends SubCommand {}
@Declare({ name: 'typo', description: 'typo' })
@Group('typo')
export class Typo extends SubCommand {}
@Declare({ name: 'system', description: 'system' })
@Group(sharedGroups, 'sys')
export class System extends SubCommand {}
@Declare({ name: 'alias', description: 'alias' })
@Group('system')
export class AliasSub extends SubCommand {}
@Declare({ name: 'template', description: 'template' })
@Group(`templated`)
export class Templated extends SubCommand {}
const dynamic = 'mod' as string;
@Declare({ name: 'dynamic', description: 'dynamic' })
@Group(dynamic)
export class Dynamic extends SubCommand {}
@Declare({ name: 'ungrouped', description: 'ungrouped' })
export class Ungrouped extends SubCommand {}
export const Expression = class extends SubCommand {};

// What @AutoLoad finds in this directory: the default export of a module of the program.
@Declare({ name: 'default', description: 'default' })
@Group('elsewhere')
export default class DefaultSub extends SubCommand {}
