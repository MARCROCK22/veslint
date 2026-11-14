declare const url: string;
declare const options: RequestInit;
const head = 'head';

// Reported.
fetch(url, { body: 'a' });
fetch(url, { method: 'GET', body: 'a' });
fetch(url, { method: 'get', body: 'a' });
fetch(url, { method: head, body: 'a' } as RequestInit);
new Request(url, { method: 'HEAD', body: 'a' });
fetch(url, { 'body': 'a', ['method']: 'GET' });
fetch(url, { ...options, method: 'GET', body: 'a' });
const method = 'head';
fetch(url, { method, body: 'a' });

// Not reported.
fetch(url, { method: 'POST', body: 'a' });
fetch(url, { method: 'GET', body: undefined });
fetch(url, { method: 'GET', body: null });
fetch(url, { method: 'GET', body: void 0 });
fetch(url, { method: 'GET', ...options, body: 'a' });
fetch(url, options);
fetch(url);
fetch?.(url, { body: 'a' });
let mutable = 'get';
fetch(url, { method: mutable, body: 'a' });
mutable = 'post';
export {};
