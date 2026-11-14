import def1, {readFileSync} from 'node:fs';
import { writeFileSync } from 'node:fs';
import {existsSync } from 'node:fs';
import def2, {} from 'node:path';
import {} from 'node:os';
import { } from 'node:util';
import * as ns1 from 'node:url';
import type {Stats} from 'node:fs';
import data1 from './data.json' with {type: 'json'};
import data2 from './data2.json' with { type: 'json' };
import {d3} from './data3.json' with {type: 'json'};
import data4 from './data4.json' with {};
import data5 from './data5.json' with { };
export * from './data6.json' with {type: 'json'};
export * from './data7.json' with { };
export {d8} from './data8.json' with {type: 'json'};
export {def1, def2 };
export { ns1 , data1};
export {};
export { };
export {
  readFileSync,
};

const o1 = {a: 1};
const o2 = { a: 1 };
const o3 = {a: 1 };
const o4 = { a: 1};
const o5 = {};
const o6 = { };
const o7 = {		};
const o8 = {  };
const o9 = { /* c */ };
const o10 = {/* c */ a: 1 /* d */};
const o11 = { // line
  a: 1 };
const o12 = {
  a: 1};
const o13 = {a: {b: 1}};
const o14 = { a: { b: 1 } };
const o15 = {a: [1, 2]};
const o16 = { a: [ 1, 2 ] };
const o17 = {a: b1[0]};
const o18 = {a: { }};
const {a: p1, b: p2} = { a: 1, b: 2 };
const { c: p3 }: {c: number} = { c: 1 };
const {d: {e: p4}} = { d: { e: 1 } };
function f1({x, y}: {x: number, y: number}): number { return x + y; }
function f2({ x }: { x: number } = { x: 1 }): number { return x; }
declare const b1: number[];
export const ex1 = {};
export const ex2 = { };
export function ex3(): void { }
export class Ex4 { }

type T1 = {a: number};
type T2 = { a: number };
type T3 = {};
type T4 = { };
type T5 = {[key: string]: number};
type T6 = { [key: string]: number };
type T7 = {readonly [key: string]: number};
type T8 = {[K in 'a' | 'b']: K};
type T9 = { [K in 'a' | 'b']: K };
type T10 = {a: {b: number}};
type T11 = {a: [number, string]};
type T12 = {a: {[K in 'x']: K}};
type T13 = {a: string[]};
type T14 = { a: Record<string, number>[ 'x' ] };
interface I1 {a: number}
interface I2 { a: number }
interface I3 {}
interface I4 { }
interface I5 {[key: string]: number}
interface I6 {a: {b: number}}
enum E1 {A, B}
enum E2 { A, B }
enum E3 {}
enum E4 { }
declare module 'm1' {export const x: number;}
const nested = {a: {b: {c: 1}}};
void def1; void readFileSync; void writeFileSync; void existsSync; void def2; void ns1;
void data1; void data2; void d3; void data4; void data5;
void o1; void o2; void o3; void o4; void o5; void o6; void o7; void o8; void o9; void o10;
void o11; void o12; void o13; void o14; void o15; void o16; void o17; void o18;
void p1; void p2; void p3; void p4; void f1; void f2; void E1; void E2; void E3; void E4; void nested;
export type { Stats, T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, I1, I2, I3, I4, I5, I6 };
export const nbsp = { };
export const nbsp2 = {   };
export const feff = {﻿};
export type N = { };
