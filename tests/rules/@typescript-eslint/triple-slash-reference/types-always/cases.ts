/// <reference types="foo" />
/// <reference path="./missing-file.ts" />
/// <reference lib="es2017" />
/// <reference types='bar' />
import * as foo from 'foo';
import bar = require('bar');
export {};
