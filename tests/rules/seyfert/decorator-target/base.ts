// Classes of another module of the project.
import { Command, SubCommand } from 'seyfert';

export abstract class RemoteSub extends SubCommand {}
export abstract class RemoteCommand extends Command {}
export { SubCommand as ProjectSub } from 'seyfert';
