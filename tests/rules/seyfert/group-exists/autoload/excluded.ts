import { Declare, Group, SubCommand } from 'seyfert';

@Declare({ name: 'excluded', description: 'd' })
@Group('excluded')
export default class Excluded extends SubCommand {}
