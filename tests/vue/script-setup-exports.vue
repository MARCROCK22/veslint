<script setup lang="ts" generic="T extends string, U = number, V extends (a: T) => void = () => void">
import A from './a'
export { a as b, c }
export const x = 1
const p = defineProps<{ t: T; u: U }>()
export default {}
export * from 'y'
let a = 1, c = 2
function f(this: void) {}
</script>
<script lang="ts">export const a = 1, c = 2</script>
<template><comp :t="p.t" @e="f" /></template>
