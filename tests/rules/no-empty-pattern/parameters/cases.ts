// Not reported with allowObjectPatternsAsParameters.
function f1({}: object) {}
function f2({} = {}) {}
const g = ({}) => {};
const h = function ({} = ({})) {};

// Reported anyway.
function f3({} = { a: 1 }) {}
function f4({ a: {} }: any) {}
function f5([]: unknown[]) {}
const {} = {};
