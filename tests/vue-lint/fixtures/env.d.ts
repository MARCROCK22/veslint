// What the fixtures need of Vue, without its package: the `*.vue` shim other files import an SFC
// through, `vue`'s reactivity and the compiler macros, which Vue declares as globals.
declare module '*.vue' {
  const component: { name?: string };
  export default component;
}

declare module 'vue' {
  export interface Ref<T> {
    value: T;
  }
  export function ref<T>(value: T): Ref<T>;
  export function computed<T>(getter: () => T): Readonly<Ref<T>>;
  export function onMounted(hook: () => void | Promise<void>): void;
}

declare function defineProps<T>(): T;
declare function defineEmits<T>(): T;
declare function defineExpose(exposed?: Record<string, unknown>): void;
declare function withDefaults<T, D extends Partial<T>>(props: T, defaults: D): T;
declare function defineModel<T>(): { value: T };
