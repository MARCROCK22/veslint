// The program has seyfert's root module: this file imports it.
import { Command as RootCommand } from 'seyfert';

// Reported, with the fix on the first name when every name can come from the root.
import { Command } from 'seyfert/lib/commands';
import { Declare, Options as Opts } from 'seyfert/lib/commands/decorators';
import type { CommandContext } from 'seyfert/lib/commands';
import { type OptionsRecord, SubCommand } from 'seyfert/lib/commands/applications/chat';
import { Formatter } from "seyfert/lib/common";
import { Logger } from 'seyfert/lib';
import {
  // a comment
  Client,
} from 'seyfert/lib/client';
/* 😀 */ import { createStringOption } from 'seyfert/lib/commands/applications/options';
import { 'createIntegerOption' as integerOption } from 'seyfert/lib/commands/applications/options';

// Reported without a fix: a name the root does not export, or a default import beside it.
import { delay, Formatter as SameFormatter } from 'seyfert/lib/common';
import Default, { Logger as SameLogger } from 'seyfert/lib/common';

// Not reported.
import * as Commands from 'seyfert/lib/commands';
import 'seyfert/lib/commands';
import {} from 'seyfert/lib/commands';
import { delay as wait } from 'seyfert/lib/common';
// @ts-expect-error: no such module
import { Command as Elsewhere } from 'seyfert/library';
export { Command as Reexported } from 'seyfert/lib/commands';
const lazy = import('seyfert/lib/commands');

export type { CommandContext, OptionsRecord };
export { Client, Command, Commands, createStringOption, Declare, Default, delay, Elsewhere, Formatter, integerOption, lazy };
export { Logger, Opts, RootCommand, SameFormatter, SameLogger, SubCommand, wait };
