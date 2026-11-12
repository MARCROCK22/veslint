// `export =` of something that is not a plain identifier, and `export default` of an expression.
declare const holder: { member: number };
export = holder.member;
