// Not reported with exceptions for Object.
(Object.prototype as any).a = 1;

// Reported anyway.
(Array.prototype as any).b = 1;
