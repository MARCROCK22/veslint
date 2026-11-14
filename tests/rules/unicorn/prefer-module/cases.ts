/* global require, module, exports, __dirname, __filename */
'use strict';

function strict() {
	'use strict';
	return 1;
}

const dirname = __dirname;
const filename = __filename;
const both = {__dirname, __filename};
const constructed = new __dirname.constructor('text');
const asserted = new __filename!.constructor('text');
if (__dirname.startsWith('/project/')) {
	strict();
}

require('side-effect');
require( (('parenthesized')) );
((require))('callee');
const lodash = require('lodash');
const {map, filter: keep} = require('lodash/fp');
const {a   :first, b:   second} = require(`template`);
const data = require('./data.json');
const {fromJson} = require('./data.json');
const typed: Typed = require('typed');
let mutable = require('mutable');
const several = require('one'), more = require('two');
const resolved = require.resolve('foo');
const computed = require(name);
function load() {
	return require('inside');
}

exports = lodash;
module.exports = lodash;
exports.named = lodash;
module.exports.named = lodash;
exports.commented /* note */ = lodash;
exports['quoted'] = lodash;
module.exports.deep.deeper = lodash;
exports += lodash;
const parent = module.parent;
const exported = module.exports;

type module = number[];
type ModuleRegistry = {[module: string]: string};
type Exports = {[exports: string]: string};
interface Required {
	require(id: string): unknown;
}

export {dirname, filename, both, constructed, asserted, mutable, several, more, resolved, computed, load, parent, exported, typed, data, fromJson, map, keep, first, second};
