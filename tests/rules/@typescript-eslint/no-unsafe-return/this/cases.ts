// no-unsafe-return with noImplicitThis disabled.
function withThis() { return this; }
function withThisMember() { return this.a; }
const arrow = function () { return this.method(); };
void [withThis, withThisMember, arrow];
