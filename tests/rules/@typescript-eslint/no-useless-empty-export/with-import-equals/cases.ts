// An import-equals declaration of a module counts as another export.
import fs = require('./cases');
export {};
export {};
void fs;
