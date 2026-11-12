import { Declare, Group, SubCommand } from 'seyfert';

@Declare({ name: 'upper', description: 'd' })
@Group('upper')
export default class Upper extends SubCommand {}
