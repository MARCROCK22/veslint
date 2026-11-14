// allowForKnownSafeCalls and allowForKnownSafePromises, with every kind of specifier.
import { fileApi, fileSafe, fileTask, fileWrongPath, dotPathTask, pathTask, rootPathTask, wrongPathTask } from './other';
import { subTask } from './sub/deep';
import { innerSafe, innerTask, pkgApi, pkgDot, pkgFileTask, pkgPartial, pkgSafe, pkgTask, pkgWrong } from 'fake-pkg';
import { scopedSafe, scopedTask } from '@scope/pkg';
import { typedSafe, typedTask } from '@other/lib';
import { noVersionSafe, noVersionTask } from 'noversion';
import { Nested, virtualSafe, virtualTask } from 'virtual-pkg';
import { outsideTask, unexportedTask } from 'outside-mod';

declare function bareSafe(): Promise<void>;
declare function unlisted(): Promise<void>;
declare function libTask(): PromiseLike<number> & Promise<number>;
declare class LocalPromise<T> extends Promise<T> {}
declare function localTask(): LocalPromise<number>;
declare const cond: boolean;

async function calls() {
  // allowForKnownSafeCalls: by the name of the callee.
  bareSafe();
  unlisted();
  fileSafe();
  fileWrongPath();
  pkgSafe();
  pkgWrong();
  pkgPartial();
  pkgDot();
  innerSafe();
  scopedSafe();
  typedSafe();
  noVersionSafe();
  virtualSafe();
  (bareSafe)();
  bareSafe?.();
  // By the type of the callee.
  fileApi.method();
  fileApi.wrongPathMethod();
  fileApi.other();
  pkgApi.method();
  pkgApi.other();
  // Only the call that is the whole statement counts.
  cond ? bareSafe() : unlisted();
  bareSafe().finally(() => {});
  void unlisted();
}

async function promises() {
  // allowForKnownSafePromises: by the type of the expression. In a single run (the eslint command
  // without --fix), typescript-estree 8.72 takes the file from a Program whose current directory,
  // which a `path` is relative to, is the one ESLint runs in: `other.ts` misses, the path from
  // the root of the project does not.
  rootPathTask();
  fileTask();
  pathTask();
  dotPathTask();
  wrongPathTask();
  subTask();
  pkgTask();
  pkgFileTask();
  innerTask();
  scopedTask();
  typedTask();
  noVersionTask();
  virtualTask();
  Nested.Deeper.deepTask();
  globalAugmentTask();
  outsideTask();
  unexportedTask();
  libTask();
  localTask();
  cond ? fileTask() : localTask();
  [fileTask(), fileTask()];
  [localTask()];
}
export { calls, promises };
