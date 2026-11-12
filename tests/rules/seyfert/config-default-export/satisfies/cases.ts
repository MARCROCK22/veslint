import { config, type BotConfig } from 'seyfert';
// `satisfies` is unwrapped like `as`.
export default config.bot({ token: 't', locations: { base: 'src' } }) satisfies BotConfig;
