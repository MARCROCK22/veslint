import data from './data.json' with { type: 'json' };
import data2 from './data.json' with { 'type': 'json' };
export * from './data.json' with { type: 'json' };
export { default as d } from './data.json' with { 'type': 'json' };
export { data, data2 };
import data3 from './data.json' with { type: 'json', 'mode': 'x' };
export { data3 };
