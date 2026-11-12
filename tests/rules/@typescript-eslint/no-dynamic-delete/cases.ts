// no-dynamic-delete: `delete` of a computed member whose key is not a string or number literal,
// or `-` and a number literal.
declare const container: Record<string, number>;
declare const key: string;
declare const index: number;

delete container[key];
delete container[index];
delete container[`k`];
delete container['a' + 'b'];
delete container[+1];
delete container[1n];
delete container[-1n];
delete container[-(-1)];
delete container[true as unknown as string];
delete (container[key]);
delete container[(key)];

// Acceptable keys, and what is not a computed member.
delete container['a'];
delete container[0];
delete container[-1];
delete container[-(1)];
delete container[('b')];
delete container.a;
delete container?.[key];
delete (container as any)?.[key];
