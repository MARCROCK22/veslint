/* exported exportedTop, exportedFn */
// sourceType "script": the declarations of the top level are variables of the global scope, where
// an `/* exported */` comment marks them as used.
var exportedTop = 1;
var unusedTop = 2;
function exportedFn() {}
function unusedFn() {}
class configUnused {}
class configUsed {}
new configUsed();
