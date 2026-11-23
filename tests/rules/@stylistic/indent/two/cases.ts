function f(a: number) {
  if (a) {
    return a;
  }
    return 0;
}

const o = {
  a: {
      b: 1,
  },
};

const chained = [1, 2]
  .map(x => x)
    .filter(Boolean);

switch (o.a) {
  case 1:
  break;
}

interface I {
  a: number;
   b: string;
}
