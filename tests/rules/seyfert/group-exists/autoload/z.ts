import { Declare, Group, SubCommand } from 'seyfert';

// A default export of a name that is a class.
@Declare({ name: 'named', description: 'd' })
@Group('named')
class Named extends SubCommand {}
export default Named;
