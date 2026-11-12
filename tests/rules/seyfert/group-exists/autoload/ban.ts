import { Declare, Group, SubCommand } from 'seyfert';

@Declare({ name: 'ban', description: 'd' })
@Group('mod')
export default class Ban extends SubCommand {}
