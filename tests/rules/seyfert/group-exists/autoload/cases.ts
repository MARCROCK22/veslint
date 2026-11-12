import { AutoLoad, Command, Declare, Groups } from 'seyfert';

// Every subcommand this directory and the ones in it export by default, but the groups declared.
@Declare({ name: 'admin', description: 'admin' })
@AutoLoad()
@Groups({ mod: { defaultDescription: 'Moderation' } })
export default class Admin extends Command {}
