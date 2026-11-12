import { Declare, Group, SubCommand } from 'seyfert';

@Declare({ name: 'kick', description: 'd' })
@Group('kick')
export default class Kick extends SubCommand {}
