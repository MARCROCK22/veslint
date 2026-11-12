import { config, type BotConfig } from 'seyfert';
import * as Seyfert from 'seyfert';
import { config as seyfertConfig } from 'seyfert';
import { projectConfig } from './reexport';

const locations = { base: 'src', commands: 'commands' };
const http = { token: 't', publicKey: 'p', applicationId: 'a', locations };

// The result is not the file's `export default`.
const bot = config.bot({ token: 't', locations });
export const server = config.http(http);
seyfertConfig.bot({ token: 't', locations });
Seyfert.config.http(http);
projectConfig.bot({ token: 't', locations });
export function make() {
  return config.bot({ token: 't', locations });
}
export const copy = { ...config.bot({ token: 't', locations }) };
export const intents = config.bot({ token: 't', locations }).intents;
export const parenthesized = (config.bot({ token: 't', locations }));
export const chained = config?.bot({ token: 't', locations });
export const both = [config.bot({ token: 't', locations }), /* 😀 */ config.http(http)];
export const multiLine =
  config
    .http(http);

// Not seyfert's config, or not a call of its bot or http.
const local = { bot: (data: unknown) => data, http: (data: unknown) => data };
local.bot({});
local.http({});
config['bot']({ token: 't', locations });
void config.bot;
config.bot.call(config, { token: 't', locations });
const { bot: unbound } = config;
unbound({ token: 't', locations });

// The default export, behind two `as`.
export default config.bot({ token: 't', locations: { ...locations, langs: 'langs' }, intents: bot.intents }) as unknown as BotConfig;
