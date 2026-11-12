/* exported exportedVar, exportedFn, notDeclared */
/* global declaredGlobal: writable */
// A script: its declarations are variables of the global scope.
var exportedVar = 1;
var plainVar = exportedVar;
let lexical = plainVar;
const constant = lexical;
function exportedFn() { return constant; }
function plainFn() { return declaredGlobal; }
class TopClass {}
type TopType = TopClass;
interface TopIface { v: TopType }
enum TopEnum { A }
namespace TopNs { export const x = 1; }
implicit = plainFn();
declaredGlobal = TopEnum.A + TopNs.x;
var Array;
let shadowsLib: Partial<TopIface>;
with (TopNs) { x; plainVar; }
function sloppy() { implicitInFunction = 1; with (TopNs) { x; } }
this;
