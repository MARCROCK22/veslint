import { Group, Command } from 'seyfert';

// A decorator after `export default`, on a class without a name.
export default @Group('admin') class extends Command {}
