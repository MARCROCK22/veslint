import { config } from 'seyfert';
// `export =` is not `export default`.
// @ts-expect-error: an export assignment is not for ECMAScript modules
export = config.bot({ token: 't', locations: { base: 'src' } });
