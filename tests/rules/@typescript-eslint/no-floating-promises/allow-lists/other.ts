export class FilePromise<T> extends Promise<T> {}
export class PathPromise<T> extends Promise<T> {}
export class DotPathPromise<T> extends Promise<T> {}
export class WrongPathPromise<T> extends Promise<T> {}
export declare function fileSafe(): Promise<void>;
export declare function fileWrongPath(): Promise<void>;
export declare function fileTask(): FilePromise<number>;
export declare function pathTask(): PathPromise<number>;
export declare function dotPathTask(): DotPathPromise<number>;
export declare function wrongPathTask(): WrongPathPromise<number>;
export declare const fileApi: { method(): Promise<void>; wrongPathMethod(): Promise<void>; other(): Promise<void> };
