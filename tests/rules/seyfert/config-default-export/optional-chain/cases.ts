import { config } from 'seyfert';
// An optional call is in a ChainExpression, which is not the default export.
export default config?.bot({ token: 't', locations: { base: 'src' } });
