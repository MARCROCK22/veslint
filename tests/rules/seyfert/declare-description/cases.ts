import {
  Command,
  ContextMenuCommand,
  createIntegerOption,
  createStringOption,
  Declare,
  Options,
  SubCommand,
} from 'seyfert';
import * as Seyfert from 'seyfert';
import { createUserOption as user } from 'seyfert';
import { remoteCommand, remoteOption } from './options';

// Valid: at most 100 code points, however many UTF-16 units they take.
@Declare({ name: 'limit', description: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' })
class Limit extends Command {}
@Declare({ name: 'astral', description: '😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀' })
class Astral extends Command {}
@Declare({ name: 'combining', description: 'éééééééééééééééééééééééééééééééééééééééééééééééééé' })
class Combining extends Command {}
@Declare({ name: 'escapes', description: '\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9' })
class Escapes extends SubCommand {}

// Reported: empty, or longer than 100 code points.
@Declare({ name: 'empty', description: '' })
class Empty extends Command {}
@Declare({ name: 'long', description: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' })
class Long extends SubCommand {}
@Declare({ name: 'astral-long', description: '😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀' })
class AstralLong extends Command {}
@Declare({ name: 'combining-long', description: 'ééééééééééééééééééééééééééééééééééééééééééééééééééé' })
class CombiningLong extends Command {}
@Declare({ name: 'escapes-long', description: '\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}\u{1F600}' })
class EscapesLong extends Command {}
@Seyfert.Declare({ name: 'template', description: `` })
class Template extends Command {}
@Declare({ name: 'wrapped', description: ('') })
class Parenthesized extends Command {}
@Declare({ name: 'as', description: '' as string })
class As extends Command {}
@Declare({ name: 'non-null', description: ''! })
class NonNull extends Command {}
/* 😀 */ @Declare({ name: 'after-astral', 'description': '' }) class AfterAstral extends Command {}
@Declare({
  name: 'multi-line',
  description:
    '',
})
class MultiLine extends Command {}

// Not a literal: skipped.
const text = '';
@Declare({ name: 'shorthand', description: text })
class Variable extends Command {}
@Declare({ name: 'assertion', description: <string>'' })
class TypeAssertion extends Command {}
@Declare({ name: 'expression', description: `${text}` })
class TemplateExpression extends Command {}
@Declare({ name: 'call', description: 'a'.repeat(101) })
class Call extends Command {}

// Only chat commands: not a context menu, nor a class that extends nothing.
@Declare({ name: 'menu', description: '' })
class Menu extends ContextMenuCommand {}
@Declare({ name: 'plain', description: '' })
class Plain {}

// Through a `const`: here it is reported where it is written, from another module at the argument.
const local = {
  name: 'local',
  description: '',
};
@Declare(local)
class Local extends Command {}
@Declare(remoteCommand)
class Remote extends Command {}

// The descriptions of options, made by seyfert's builders.
const optionText = { description: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' };
@Declare({ name: 'options', description: 'options' })
@Options({
  empty: createStringOption({ description: '' }),
  long: createIntegerOption({ description: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }),
  astral: createStringOption({ description: '😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀' }),
  aliased: user({ description: `` }),
  namespaced: Seyfert.createBooleanOption({ description: '' }),
  local: createStringOption(optionText),
  remote: createStringOption(remoteOption),
})
class WithOptions extends Command {}
// A builder that is not seyfert's.
function createLocalOption(options: { description: string }) {
  return options;
}
createLocalOption({ description: '' });

export { As, Astral, AstralLong, AfterAstral, Call, Combining, CombiningLong, Empty, Escapes, EscapesLong, Limit, Local, Long };
export { Menu, MultiLine, NonNull, Parenthesized, Plain, Remote, Template, TemplateExpression, TypeAssertion, Variable, WithOptions };
