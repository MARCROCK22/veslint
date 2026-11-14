declare const foo: number;
declare function bar(): void;
// 79.0.0: the moved `break` uses the line ending of the file.
switch (foo) {
	case 1: {
		bar();
	}
	break;
}
