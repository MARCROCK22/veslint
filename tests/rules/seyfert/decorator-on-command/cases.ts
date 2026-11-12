import {
  AutoLoad,
  BaseCommand,
  Command,
  ComponentCommand,
  ContextMenuCommand,
  Declare,
  EntryPointCommand,
  Locales,
  LocalesT,
  Middlewares,
  ModalCommand,
  Options,
  SubCommand,
} from 'seyfert';
import * as Seyfert from 'seyfert';
import { Declare as D, Middlewares as Uses } from 'seyfert';
import { ButtonBase, FormBase, NotACommand } from './base';

// Valid: on every command base, and @Middlewares on components too.
@Declare({ name: 'chat', description: 'chat' })
@Options({})
@Locales({})
@LocalesT()
@Middlewares([])
class Chat extends Command {}
@D({ name: 'sub', description: 'sub' })
@Seyfert.Options({})
class Sub extends SubCommand {}
@Declare({ name: 'menu', type: 2 })
class Menu extends ContextMenuCommand {}
@Declare({ name: 'entry', description: 'entry' })
class Entry extends EntryPointCommand {}
@Locales({})
class Base extends BaseCommand {}
@Middlewares([])
class Button extends ComponentCommand {}
@Uses([])
class Form extends ModalCommand {}
@Middlewares([])
class RemoteButton extends ButtonBase {}
@Seyfert.Middlewares([])
class RemoteForm extends FormBase {}
function mixin<T extends abstract new (...args: never[]) => object>(base: T) {
  return base;
}
@Declare({ name: 'mixed', description: 'mixed' })
class Mixed extends mixin(Command) {}
// Not one of these decorators, or not seyfert's.
@AutoLoad()
class Loaded extends ComponentCommand {}
function Options2(_options: object) {
  return (_target: unknown) => {};
}
@Options2({})
class Unrelated {}

// Invalid: reported with seyfert's name of the decorator.
@Declare({ name: 'button', description: 'button' })
@Middlewares([])
class DeclaredButton extends ComponentCommand {}
@Options({})
class OptionsOnForm extends FormBase {}
@D({ name: 'plain', description: 'plain' }) @Uses([])
class Plain {}
@Seyfert.LocalesT()
class Remote extends NotACommand {}
@Locales({}) /* 😀 */ @Middlewares([])
class Local extends Unrelated {}
// @ts-expect-error: with experimentalDecorators, a class expression takes no decorator
const Expression = @Declare({ name: 'expression', description: 'expression' }) class {};
function inside() {
  @Middlewares([])
  class Nested {}
  return Nested;
}

export { Base, Button, Chat, DeclaredButton, Entry, Expression, Form, inside, Loaded, Local, Menu, Mixed, OptionsOnForm };
export { Plain, Remote, RemoteButton, RemoteForm, Sub };
