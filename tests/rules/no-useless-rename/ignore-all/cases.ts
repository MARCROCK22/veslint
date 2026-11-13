import { readFile as readFile } from 'node:fs';

declare const obj: any;

// Not reported with every ignore option.
const { a: a } = obj;
export { readFile as readFile };
