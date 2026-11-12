// Reported: every specifier has its own `type`.
import { type A } from 'mod';
import { type B, type C } from 'mod';
import { type D as E, type F as G } from 'mod';
import { /* before */ type H } from 'mod';
import { type /* between */ I } from 'mod';
import { type J /* after */ } from 'mod';
import {
  type K,
  type L, // trailing
} from 'mod';
import { type type } from 'mod';
import { type 'string-name' as M } from 'mod';
import /* after import */ { type N } from 'mod';
import{type P}from'mod';

// Not reported.
import type { Q } from 'mod';
import type { type R } from 'mod';
import { S, type T } from 'mod';
import { type U, V } from 'mod';
import W, { type X } from 'mod';
import * as Y from 'mod';
import {} from 'mod';
import 'mod';
import Z = require('mod');
import type ZZ = require('mod');
import { type } from 'mod';
import { type as as } from 'mod';
export { type A2 } from 'mod';
export type { A3 } from 'mod';
