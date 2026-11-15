declare const cond: boolean;
declare function work(): void;

function sameLine() {
	work();
}

function nextLine()
{
	work();
}

function oneLine() { work(); }

function emptyBody() {}

function emptyNextLine()
{}

if (cond) {
	work();
} else {
	work();
}

if (cond) {
	work();
}
else {
	work();
}

if (cond)
{
	work();
}
else
{
	work();
}

if (cond) { work(); } else { work(); }

if (cond) {
	work();
} else if (cond) {
	work();
}

if (cond) work();
else {
	work();
}

try {
	work();
} catch (e) {
	work();
} finally {
	work();
}

try {
	work();
}
catch (e) {
	work();
}
finally {
	work();
}

try { work(); } catch { work(); }

try {
	work();
} /* comment */
finally {
	work();
}

while (cond) { work();
}

for (;;) {
	work(); }

for (;;)
// comment
{
	work();
}

do {
	work();
} while (cond);

switch (cond) {
	case true:
		work();
}

switch (cond)
{
	case true: {
		work();
	}
}

switch (cond) { case true: work(); }

switch (cond) {}

class Klass {
	method() {
		work();
	}

	static {
		work();
	}

	static
	{
		work();
	}

	static { work(); }
}

class OneLine { x = 1; }

class NextLine
{
	x = 1;
}

namespace Space {
	export const a = 1;
}

namespace Inline { export const b = 1; }

declare module 'mod'
{
	export const c: number;
}

{
	work();
}

{ work(); }

const arrow = () => {
	work();
};

const arrowOneLine = () => { work(); };

const objectLiteral = { a: 1 };

label: {
	work();
}

const fnExpression = function ()
{
	return 1;
};
