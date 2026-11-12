import { Command, createStringOption, createUserOption, Declare, Options, SubCommand } from 'seyfert';
import * as Seyfert from 'seyfert';
import { createIntegerOption as integer, Options as Opts } from 'seyfert';
import { remoteBuilt, remoteOptions, remoteRaw } from './options';

declare function makeOption(): { description: string };
const built = createStringOption({ description: 'built' });
const builtAlias = built;
let changing = createStringOption({ description: 'changing' });
const common = { user: createUserOption({ description: 'user' }) };
const commonRaw = { raw: { description: 'raw' } };

// Valid: every option is a call of a seyfert builder, directly or through a `const`.
@Declare({ name: 'valid', description: 'valid' })
@Options({
  direct: createStringOption({ description: 'direct' }),
  aliased: integer({ description: 'aliased' }),
  namespaced: Seyfert.createNumberOption({ description: 'namespaced' }),
  wrapped: (createStringOption({ description: 'wrapped' }) as never),
  built,
  builtAlias,
  remoteBuilt,
  ...common,
  ...makeOption(),
})
class Valid extends Command {}

// Reported at the value, or at the property when there is no value to point at.
@Declare({ name: 'invalid', description: 'invalid' })
@Opts({
  object: { description: 'raw' },
  call: makeOption(),
  reference: createStringOption,
  changing,
  remoteRaw,
  method() {},
  get accessor() { return createStringOption({ description: 'accessor' }); },
  'string-key': 'x',
  ['computed']: 'x',
  [`template`]: 'x',
  [Symbol.iterator]: 'x',
  10: 'x',
  ñame: 'x',
  parenthesized: ('x'),
  /* 😀 */ astral: 'x',
})
class Invalid extends SubCommand {}

// Through a `let` and through a cycle of `const`s: what is left at the end is reported.
const first: object = second;
const second: object = first;
@Declare({ name: 'cycle', description: 'cycle' })
@Options({ loop: first })
class Cycle extends Command {}

// Options in a `const` of this file are reported there, those of another module at the argument.
const local = {
  local: { description: 'local' },
};
@Declare({ name: 'local', description: 'local' })
@Options(local)
class Local extends Command {}
@Declare({ name: 'remote', description: 'remote' })
@Options(remoteOptions)
class Remote extends Command {}

// Not reported: the plugin marks the object a spread leads to as seen before it reads it.
@Declare({ name: 'spread-raw', description: 'spread-raw' })
@Options({ ...commonRaw })
class SpreadRaw extends Command {}

// Not an object that can be read: skipped.
@Declare({ name: 'subcommands', description: 'subcommands' })
@Options([Invalid])
class Subcommands extends Command {}
const args = [{}] as const;
@Declare({ name: 'spread', description: 'spread' })
@Options(...args)
class Spread extends Command {}

export { Cycle, Local, Remote, Spread, SpreadRaw, Subcommands, Valid };
