// allowPattern is tested against the value as a string, also for `true`, `false` and `null`.
declare const obj: Record<string, number>;
declare const anything: any;
anything[true];
anything[false];
anything[null];
obj['item_12'];
obj['item12'];
obj['ab'];
obj['abc'];
obj['$a'];
obj[`a$`];
