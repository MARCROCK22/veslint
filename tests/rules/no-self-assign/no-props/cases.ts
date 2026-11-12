// no-self-assign with props: false: members are not checked.
let a = 1;
declare let o: { x: number };

a = a;
o.x = o.x;
o['x'] = o.x;
