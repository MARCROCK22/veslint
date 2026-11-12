// Options written in another module of the project.
import { createStringOption } from 'seyfert';

export const remoteOptions = { built: createStringOption({ description: 'built' }), raw: { description: 'raw' } };
export const remoteBuilt = createStringOption({ description: 'remote' });
export const remoteRaw = { description: 'remote raw' };
