// unicorn/prefer-export-from: with `checkUsedVariables: false`, used imports are skipped.
import {used} from 'used-module';
export {used};
console.log(used);

import {exported, unused} from 'partly-module';
export {exported};

import {alone} from 'alone-module';
export {alone};

import {once, twice} from 'twice-module';
export {once};
export default twice;

import {commented, idle} from 'commented-module';
export {commented /* inside */};

import type {TypeOnly} from 'type-module';
export type {TypeOnly};
