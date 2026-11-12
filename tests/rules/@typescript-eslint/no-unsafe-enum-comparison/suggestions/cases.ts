import { Computed, Remote } from './other';

enum Fruit {
  Apple = 'apple',
  Banana = 'banana',
  'dragon fruit' = 'dragon',
  "it's" = 'quoted',
}
enum Num {
  Zero,
  One,
  Minus = -1,
  Big = 1e3,
}
enum Mixed {
  A = 0,
  B = 'b',
}
declare const fruit: Fruit;
declare const num: Num;
declare const mixed: Mixed;
declare const remote: Remote;
declare const computed: Computed;
declare const fruitOrNum: Fruit | Num;
declare const text: string;
declare const count: number;
const apple = 'apple';

// The right side becomes the key of the left side's enum.
fruit === 'apple';
fruit === "banana";
fruit === `dragon`;
fruit === 'quoted';
computed === 'one';
computed === 'two';
fruit === ('apple');
fruit == 'ap' + 'ple';
num === 0;
num === 1;
num === -1;
num === 1000;
num === 1 + 0;
num < 1;
mixed === 0;
mixed === 'b';
remote === 1;
remote === 2;
fruitOrNum === 'banana';
fruitOrNum === 1;
Fruit.Apple === 'banana';

// The left side becomes the key of the right side's enum.
'apple' === fruit;
0 === num;
('banana') !== fruit;
2 === remote;

// No key: no suggestion.
fruit === 'cherry';
fruit === text;
fruit === apple;
num === 7;
num === count;
num === 0n;
mixed === 'missing';
text === fruit;

const résumé = '🎉'; fruit === 'apple';
void [résumé];
