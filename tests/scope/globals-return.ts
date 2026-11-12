// ecmaFeatures.globalReturn: the program is the body of a function.
var top = arguments;
function f() { return top; }
return f;
