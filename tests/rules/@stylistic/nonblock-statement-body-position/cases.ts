declare const cond: boolean;
declare function work(): void;
declare const list: number[];

if (cond) work();
if (cond)
	work();
if (cond) work();
else work();
if (cond) work();
else
	work();
if (cond) work();
else if (cond) work();
else if (cond)
	work();
if (cond) {
	work();
}
if (cond)
{
	work();
}
if (cond) // comment
	work();
if (cond) /* comment */ work();
while (cond) work();
while (cond)
	work();
do work(); while (cond);
do
	work();
while (cond);
for (;;) work();
for (;;)
	work();
for (const x in list) work();
for (const x in list)
	work();
for (const x of list) work();
for (const x of list)
	work();
if (cond) ;
if (cond)
	;
label: for (;;)
	break label;
