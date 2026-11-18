<template>
  <div>{{ total }}</div>
</template>

<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  name: 'Cases',
    props: {
    a: Number
  }
})
</script>

<script setup lang="ts">
import {
  ref,
    computed
} from 'vue'
import type { Ref } from 'vue'
interface Item {
  id: number
    name: string
  tags?: string[]
}
type Pair<T> =
  | [T, T]
  | null
enum Color {
  Red,
    Green = 'g'
}
const items: Ref<Item[]> = ref([])
const total = computed(() =>
  items.value
    .filter((i) => i.id > 0)
      .length
)
function sum(
  a: number,
    b: number
): number {
  if (a > b) {
  return a
  } else {
    return b
  }
}
class Box<T> implements Iterable<T> {
  private values: T[] = []
    static count = 0;
  [Symbol.iterator]() {
    return this.values[Symbol.iterator]()
  }
}
switch (sum(1, 2)) {
case 1:
  break
  default:
    sum(
      1,
      2
    )
}
const tpl = `a ${
  total.value
} b`
  /*
   * misaligned
      * block comment
 */
    const late = 1 // trailing
    // line comment
  ;[1, 2].forEach((n) => n)
const obj = {
  key: 'v',
  nested: {
  deep: true
  },
}
for (const x of [1, 2])
  sum(x, x)
try {
  sum(1, 1)
}
  catch (e) {
  throw e
} finally {
    sum(0, 0)
}
const pair: Pair<number> = [1, 2]
const asserted = (obj as unknown) satisfies unknown
</script>
