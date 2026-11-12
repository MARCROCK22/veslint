// Options of @Declare written in another module of the project.
import { ApplicationCommandType } from 'seyfert';

export const remoteWithDescription = { name: 'remote', type: ApplicationCommandType.User, description: 'remote' };
export const remoteWithoutType = { name: 'remote' };
export const nested = { menu: { name: 'nested' } };
