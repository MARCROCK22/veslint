import { Declare, Group, SubCommand } from 'seyfert';

@Declare({ name: 'warn', description: 'd' })
@Group('warn')
export default class Warn extends SubCommand {}
