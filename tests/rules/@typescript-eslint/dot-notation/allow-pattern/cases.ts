// allowPattern: names the pattern matches may stay in brackets (here, snake_case).
declare const obj: Record<string, number>;
obj['snake_case'];
obj['camelCase'];
obj['a_b_c'];
obj['plain'];
obj['Snake_case'];
obj['snake_'];
obj[`snake_case`];
obj[`plain`];
obj['snake_case_ñ'];
obj['$dollar'];
