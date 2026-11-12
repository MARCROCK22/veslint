import { CommandContext, type ComponentContext, Embed } from 'seyfert';

declare const ctx: CommandContext;
declare const maybe: CommandContext | undefined;
declare const either: CommandContext | ComponentContext;
declare const both: CommandContext & { extra: true };
declare const contexts: CommandContext[];
declare function load(): Promise<CommandContext>;
class MyContext extends CommandContext {
  // An override declared in this file: no longer seyfert's method.
  editOrReply(): never {
    throw new Error('not here');
  }
  own() {}
}
declare const mine: MyContext;

// Reported at the key of each method of a seyfert class.
const { editOrReply } = ctx;
const { deferReply, write: send } = ctx;
const { 'editResponse': edit, followup = undefined } = ctx;
const { deleteResponse } = maybe!;
const { fetchResponse } = ctx as CommandContext;
const { inGuild } = either;
const { isChat } = both;
const { me } = mine;
async function later() {
  const { guild } = await load();
  return guild;
}
const {
  /* 😀 ñ */ channel,
  ...rest
} = ctx;
function parameter({ editOrReply }: CommandContext) {
  return editOrReply;
}
const arrow = ({ editResponse }: CommandContext = ctx) => editResponse;
for (const { isComponent } of contexts) {
  void isComponent;
}
const [{ isMenu }] = contexts;
const { interaction: { respond } } = ctx;
const { toJSON } = new Embed();

// Not reported: properties and getters, a method declared here, computed keys, a type that has none.
const { client, t, author } = ctx;
const { editOrReply: overridden, own } = mine;
const { ['editOrReply']: computed } = ctx;
const { length } = 'text';
try {
  void 0;
} catch ({ message }: any) {
  void message;
}
const { reply } = { reply() {} };
// In an assignment, the type of the pattern is the one of the object literal it is in TypeScript.
let assigned: unknown;
({ editOrReply: assigned } = ctx);

export { arrow, assigned, author, channel, client, computed, deferReply, deleteResponse, edit, editOrReply, fetchResponse };
export { followup, inGuild, isChat, isMenu, later, length, me, overridden, own, parameter, reply, respond, rest, send, t, toJSON };
