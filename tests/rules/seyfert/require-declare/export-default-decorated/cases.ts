import { Command, Options } from 'seyfert';

// A decorator before `export default` is not part of the class in ESTree.
@Options({})
export default class extends Command {}
