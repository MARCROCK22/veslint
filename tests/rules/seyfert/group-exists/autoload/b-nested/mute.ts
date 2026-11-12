import { Declare, Group, SubCommand } from 'seyfert';

@Declare({ name: 'mute', description: 'd' })
@Group('mod')
export default class Mute extends SubCommand {}
