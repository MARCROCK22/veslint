#!/usr/bin/env node
/// <reference types="foo" />
/// <reference path="./missing-file.ts" />
/// <reference lib="es2017" />
///<reference types="baz"/>
/// <reference  types = 'qux' />
/// <referencetypes="nospace" />
//// <reference types="four-slashes" />
/* /// <reference types="block" /> */
/// <reference types="pipe|quote" /> // "last"
/// <reference path='single' />
/// <reference types="foo" />
//	<reference types="tab" />
/// <reference types="" />
// a comment that is not a reference
/// <reference types="bar" no-close
import * as foo from 'foo';
import foo2 = require('foo');
import baz from 'baz';
import type { Q } from 'qux';
import 'nospace';
import tab from 'tab';
import pipe from 'pipe|quote" /> // "last';
import empty from '';
import foo3 from 'foo';
declare module 'inner' {
  import bar from 'bar';
}
const lazy = import('baz');
export * from 'qux';
/// <reference types="after-first-token" />
import after from 'after-first-token';
