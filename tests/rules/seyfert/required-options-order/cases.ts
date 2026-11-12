import { Command, createBooleanOption, createStringOption, createUserOption, Declare, Options } from 'seyfert';
import * as Seyfert from 'seyfert';
import { createIntegerOption as integer } from 'seyfert';
import { remoteOptions, remoteRequired } from './options';

declare const flag: boolean;
const required = true;
const optionalOption = createStringOption({ description: 'optional', required: false });
const requiredOption = createStringOption({ description: 'required', required: true });
const config = { description: 'config', required: true } as const;
const base = { description: 'base' };

// Valid: the required options first.
@Declare({ name: 'ordered', description: 'ordered' })
@Options({
  first: createStringOption({ description: 'first', required: true }),
  second: integer({ description: 'second', required: (true) }),
  third: createUserOption({ description: 'third' }),
  fourth: createBooleanOption({ description: 'fourth', required: false }),
})
class Ordered extends Command {}

// Reported at each required option after an optional one.
@Declare({ name: 'unordered', description: 'unordered' })
@Options({
  optional: createStringOption({ description: 'optional' }),
  required: createStringOption({ description: 'required', required: true }),
  'string key': Seyfert.createNumberOption({ description: 'string key', required: true as const }),
  [`template`]: integer({ description: 'template', required: true }),
  [Symbol.iterator]: createStringOption({ description: 'symbol', required: true }),
  wrapped: (createStringOption({ description: 'wrapped', required: true }) as never),
  /* 😀 */ astral: createStringOption({ description: 'astral', required: true }),
  variable: requiredOption,
})
class Unordered extends Command {}
@Declare({ name: 'variable', description: 'variable' })
@Options({
  optional: optionalOption,
  required: createStringOption({ ...base, required: true }),
})
class AfterVariable extends Command {}

// What cannot be told apart is neither optional nor required; a builder in a `const` is read
// through it.
@Declare({ name: 'unknown', description: 'unknown' })
@Options({
  dynamic: createStringOption({ description: 'dynamic', required: flag }),
  shorthandRequired: createStringOption({ description: 'shorthand', required }),
  spread: createStringOption({ ...base }),
  configVariable: createStringOption(config),
  remote: remoteRequired,
  shorthandOption: requiredOption,
  required: createStringOption({ description: 'required', required: true }),
})
class Unknown extends Command {}
// Values that are not seyfert builders are skipped; the order of the others still counts.
@Declare({ name: 'not-builders', description: 'not builders' })
@Options({
  // @ts-expect-error: not an option
  raw: { description: 'raw' },
  optional: createStringOption({ description: 'optional' }),
  shorthandOption: requiredOption,
  call: makeOption(),
  required: createStringOption({ description: 'required', required: true }),
})
class NotBuilders extends Command {}
function makeOption() {
  return { description: 'made' };
}

// Options in a `const` of this file are reported there, those of another module at the argument.
const local = {
  optional: createStringOption({ description: 'optional' }),
  required: createStringOption({ description: 'required', required: true }),
};
@Declare({ name: 'local', description: 'local' })
@Options(local)
class Local extends Command {}
@Declare({ name: 'remote', description: 'remote' })
@Options(remoteOptions)
class Remote extends Command {}

export { AfterVariable, Local, NotBuilders, Ordered, Remote, Unknown, Unordered };
