import { config } from 'seyfert';
// The plugin reports the call, not what the file exports: a variable in between is reported.
const bot = config.bot({ token: 't', locations: { base: 'src' } });
export default bot;
