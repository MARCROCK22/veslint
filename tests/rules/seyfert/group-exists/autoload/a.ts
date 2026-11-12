import { Declare, Group, SubCommand } from 'seyfert';

@Declare({ name: 'anonymous', description: 'd' })
@Group('anonymous')
export default class extends SubCommand {}
