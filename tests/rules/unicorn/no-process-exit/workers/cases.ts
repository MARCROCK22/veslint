import { isMainThread } from 'node:worker_threads';
if (!isMainThread) process.exit(1);
