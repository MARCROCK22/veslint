import a1 from './a1.json' with { type: 'json', mode: '1', zone: '2' };
import a2 from './a2.json' with {
  type: 'json',

  mode: '1',

  zone: '2',
};
import a3 from './a3.json' with {
  type: 'json',


  mode: '1',
  zone: '2',
};
import a4 from './a4.json' with { zone: '2', mode: '1',
  type: 'json' };
export { a1, a2, a3, a4 };
