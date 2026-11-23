// The example of issue #39 (curly, nonblock-statement-body-position and multiline-ternary leave
// these lines unindented; indent re-indents them).
export function f(a: boolean, b: number): number {
	if (a) 
{return b;}
	const c = a
? b * 2
: b * 3;
	return c;
}

function g(
	x: number,
    y: number,
		z: number,
) {
  return x
		+ y;
}

const o = {
	a: 1,
		b: [
		2,
	],
};

class C {
	m() {
		if (o) {
		    return 1;
		}
	}
}

switch (o.a) {
	case 1:
		break;
case 2:
	break;
}

const t = `
	${o.a} ${
		o.a
	}
`;
