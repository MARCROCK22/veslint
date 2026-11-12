import * as Seyfert from 'seyfert';

// Through a namespace import: the call that is not the default export.
Seyfert.config.bot({ token: 't', locations: { base: 'src' } });
export default Seyfert.config.http({ token: 't', publicKey: 'p', applicationId: 'a', locations: { base: 'src' } });
