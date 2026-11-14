declare const data: unknown;
declare const init: ResponseInit;

// Fixed.
const a1 = new Response(JSON.stringify(data));
const a2 = new Response(JSON.stringify(data), init);
const a3 = new Response((JSON.stringify((data))));
const a4 = new Response(JSON.stringify({ a: 1 }),);
function a5() {
  return new
    Response(JSON.stringify(data));
}

// Reported, not fixed.
const b1 = new Response(JSON.stringify(/* c */ data));
const b2 = new Response(JSON.stringify(undefined));
const b3 = new Response(JSON.stringify(() => 1));
const b4 = new Response(JSON.stringify(class {}));
const b5 = new Response(JSON.stringify(void 0));

// Not reported.
const k1 = new Response(JSON.stringify(data, null, 2));
const k2 = new Response('text');
const k3 = Response.json(data);
const k4 = new Response(JSON?.stringify(data));
const k5 = new Response();
export { a1, a2, a3, a4, a5, b1, b2, b3, b4, b5, k1, k2, k3, k4, k5 };
