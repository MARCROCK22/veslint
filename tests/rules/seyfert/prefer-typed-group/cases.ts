import { Command, Declare, defineGroups, Group, Groups, Options, SubCommand } from 'seyfert';
import * as Seyfert from 'seyfert';
import { Group as G } from 'seyfert';
import { ProjectGroup } from './reexport';
import * as Project from './reexport';

const groups = defineGroups({ admin: { defaultDescription: 'Admin commands' } });

// The two-argument overload is the typed one.
@Declare({ name: 'typed', description: 'typed' })
@Group(groups, 'admin')
class Typed extends SubCommand {}

// A bare group name.
@Declare({ name: 'bare', description: 'bare' })
@Group('admin')
class Bare extends SubCommand {}

// Another name for seyfert's Group, by an alias, a namespace or a re-export of the project.
@G('admin')
class Aliased extends SubCommand {}
@Seyfert.Group('admin')
class Namespaced extends SubCommand {}
@ProjectGroup('admin')
class Reexported extends SubCommand {}
@Project.Group('admin')
class ReexportedNamespace extends SubCommand {}

// Parentheses around the call are not a node in ESTree.
@(Group('admin'))
class ParenthesizedCall extends SubCommand {}

// One argument of any kind; a spread may hold two.
const name = 'admin';
@Group(name)
class Identifier extends SubCommand {}
@Group(`admin`)
class Template extends SubCommand {}
const both = [groups, 'admin'] as const;
@Group(...both)
class Spread extends SubCommand {}
// @ts-expect-error: no overload takes no argument
@Group()
class NoArgument extends SubCommand {}
// @ts-expect-error: no overload takes three arguments
@Group(groups, 'admin', 'extra')
class ThreeArguments extends SubCommand {}

// The rule looks at the call, not at what the decorator is applied to.
@Declare({ name: 'parent', description: 'parent' })
@Groups({ admin: { defaultDescription: 'Admin commands' } })
@Options([Typed, Bare])
class Parent extends Command {
  // @ts-expect-error: a class decorator on a method
  @Group('admin') method() {}
}
// @ts-expect-error: with experimentalDecorators, a class expression takes no decorator
const Expression = @Group('admin') class extends SubCommand {};

// Two decorators on a line, a multi-line call, and characters of two UTF-16 units before.
@Declare({ name: 'line', description: 'line' }) @Group('admin') class OneLine extends SubCommand {}
@Group(
  // the name of the group
  'admin',
)
class MultiLine extends SubCommand {}
/* 😀 ñ */ @Group('admin') class Astral extends SubCommand {}

// Another Group: a local function, and a variable holding seyfert's.
function Local(_name: string) {
  return (_target: unknown) => {};
}
@Local('admin')
class LocalDecorator extends SubCommand {}
const Held = Group;
@Held('admin')
class HeldGroup extends SubCommand {}

export { Aliased, Astral, Expression, HeldGroup, Identifier, LocalDecorator, MultiLine, Namespaced, NoArgument, OneLine };
export { ParenthesizedCall, Parent, Reexported, ReexportedNamespace, Spread, Template, ThreeArguments };
