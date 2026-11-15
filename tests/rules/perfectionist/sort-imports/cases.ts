// Reported and fixed: groups (types, builtin and external, internal, parent, sibling and index), names and
// the lines between groups.
import { b } from './b';
import type { T } from 'types';
import { readFile } from 'node:fs';
import z from 'zod';
import path from 'path';
import { local } from '~/local';
import parent from '../parent';
import index from '.';
import type { Sibling } from './sibling';
import a from 'a';

import fs from 'fs';

import x = require('x');
// Comments move with their import.
import d from 'd'; // after d
// above c
import c from 'c';

console.log(b, readFile, z, path, local, parent, index, a, fs, x, d, c);

// Side effects stay where they are.
import 'polyfill';
import f from 'f';
import e from 'e';
import './styles.css';

// Code between imports makes another run.
import h from 'h';
import g from 'g';
console.log(f, e, h, g);

// Imports that use another import come after it.
import A = Namespace.A;
import Namespace = require('namespace');
console.log(A);

// eslint-disable comments keep an import in place.
import k from 'k';
import j from 'j';
import i from 'i'; // eslint-disable-line

// require calls, and names with specifiers.
const m = require('m');
const { l } = require('l');
import * as star from 'star';
import def, { named } from 'def';
import {
  multi,
  line,
} from 'multiline';
console.log(k, j, i, m, l, star, def, named, multi, line);

export function inner() {
  const q = require('q');
  const p = require('p');
  return [q, p];
}
// Sorted.
import { aa } from 'aa';
import { bb } from 'bb';
console.log(aa, bb);
