// The method name is read with getStaticMemberAccessValue: any static value, not only a literal.
declare const list: number[];
const filterKey = 'filter';
list[filterKey](() => true);
list['so' + 'me'](() => false);
list[`every`](() => 1);
list['\x66ind'](() => ({}));
list['map'](() => true);
// The name through a Map, a Set and Object.values.
list[new Map([[0, 'filter']]).get(0) as 'filter'](() => true);
list[[...new Set(['some'])][0] as 'some'](() => false);
list[Object.values(['every'])[0] as 'every'](() => 1);
