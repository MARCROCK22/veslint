// Names outside ASCII and with escapes: positions are bytes, names are cooked.
const ñandú = 1, 日本 = ñandú, abc = 日本, 𝒳 = abc;
function ƒ(π = 𝒳) { return π + \u{61}bc; }
export { ñandú as 'string name', ƒ };
