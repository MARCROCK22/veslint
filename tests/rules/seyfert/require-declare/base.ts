// Classes of another module of the project.
import { Command, Declare, SubCommand } from 'seyfert';

@Declare({ name: 'declared', description: 'declared' })
export class DeclaredBase extends Command {}
export abstract class UndeclaredBase extends Command {}
export abstract class UndeclaredSub extends SubCommand {}
export { Command as ProjectCommand } from 'seyfert';
