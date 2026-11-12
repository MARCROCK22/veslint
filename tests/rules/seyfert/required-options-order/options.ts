// Options written in another module of the project.
import { createStringOption } from 'seyfert';

export const remoteOptions = {
  optional: createStringOption({ description: 'optional' }),
  required: createStringOption({ description: 'required', required: true }),
};
export const remoteRequired = createStringOption({ description: 'remote', required: true });
