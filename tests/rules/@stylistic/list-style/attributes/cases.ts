// Import attributes.
import data from './data.json' with {type: 'json'};
import { name,
  version } from './package.json' with { type: 'json' };
export * from './other.json' with {type: 'json'};
export { name as n } from './package.json' with {
  type: 'json' };
export { data, name, version };
