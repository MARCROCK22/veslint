declare const obj: any;
declare let module: any;

// Reported with "never" and includeCommonJSModuleExports.
const a = function a() {};
obj.p = function p() {};
const o = { t: function t() {} };
module.exports = function exports() {};

// Not reported.
const b = function c() {};
