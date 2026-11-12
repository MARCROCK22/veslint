import { config } from 'seyfert';
// Parentheses are not a node in ESTree: the call is the default export.
export default (config.bot({ token: 't', locations: { base: 'src' } }));
