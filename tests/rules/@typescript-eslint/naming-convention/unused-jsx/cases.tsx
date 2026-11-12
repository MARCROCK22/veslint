// naming-convention with the `unused` modifier: a JSX element whose name starts in lower case is
// an intrinsic element, not a use of a variable.
const élan = () => null;
const Élan = () => null;
const lower = () => null;
const Upper = () => null;
const _ignored = () => null;
const ǅown = () => null;
const ǆown = () => null;
const Ǆown = () => null;
const ßeta = () => null;
const 日本 = () => null;
const $dollar = () => null;
const ns = { inner: () => null };
export const elements = [<élan />, <Élan />, <lower />, <Upper />, <ǅown />, <ǆown />, <Ǆown />, <ßeta />, <日本 />, <$dollar />, <ns.inner />];
