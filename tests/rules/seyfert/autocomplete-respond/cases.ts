import {
  AutocompleteInteraction,
  type ChatInputCommandInteraction,
  Command,
  createIntegerOption,
  createStringOption,
  Declare,
  Options,
} from 'seyfert';
import * as Seyfert from 'seyfert';

declare const interaction: AutocompleteInteraction;
declare const typed: AutocompleteInteraction<true, string>;
declare const namespaced: Seyfert.AutocompleteInteraction;
type Alias = AutocompleteInteraction;
declare const aliased: Alias;
class Mine extends AutocompleteInteraction {
  answer() {
    // The type of `this` is the class's own `this` type, not AutocompleteInteraction.
    this.reply();
    super.reply();
  }
}
declare const mine: Mine;
declare function get(): AutocompleteInteraction;
declare const holder: { interaction: AutocompleteInteraction };
declare const maybe: AutocompleteInteraction | undefined;
declare const either: AutocompleteInteraction | ChatInputCommandInteraction;
declare const both: AutocompleteInteraction & { extra: true };
declare const chat: ChatInputCommandInteraction;
declare const plain: { reply(): void };

// `.reply()` on seyfert's AutocompleteInteraction, or on a class that extends it.
interaction.reply();
typed.reply([]);
namespaced.reply();
aliased.reply();
mine.reply();
get().reply();
holder.interaction.reply();
maybe!.reply();
(interaction as AutocompleteInteraction).reply();
(either as AutocompleteInteraction).reply();
interaction
  // a comment between the object and the method
  .reply();
/* 😀 ñ */ interaction.reply();
void interaction.reply().then(() => interaction.reply());

// The type is a union or an intersection, not the class.
maybe?.reply();
either.reply({ type: 4, data: { content: 'pong' } });
both.reply();

// Not a call of the `reply` member, or another `reply`.
interaction.respond([]);
interaction['reply']();
void interaction.reply;
void interaction.reply.call(interaction);
const { reply } = interaction;
void reply();
chat.reply({ type: 4, data: { content: 'pong' } });
plain.reply();

// Where an autocomplete interaction usually comes from.
@Declare({ name: 'search', description: 'Search something' })
@Options({
  query: createStringOption({
    description: 'What to search',
    autocomplete: interaction => interaction.reply(),
  }),
  page: createIntegerOption({
    description: 'The page',
    async autocomplete(interaction) {
      await interaction.respond([{ name: '1', value: 1 }]);
    },
  }),
})
export class Search extends Command {
  async autocomplete(interaction: AutocompleteInteraction) {
    await interaction.reply();
    return interaction.respond([]);
  }
}
