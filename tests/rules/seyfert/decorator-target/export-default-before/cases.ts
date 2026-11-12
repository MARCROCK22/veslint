import { Groups, SubCommand } from 'seyfert';

// A decorator before `export default`, on a class without a name.
@Groups({})
export default class extends SubCommand {}
