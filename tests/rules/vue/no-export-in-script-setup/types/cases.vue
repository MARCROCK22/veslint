<script setup lang="ts">
export type T = string
export interface I {}
type V = number
export { type V as U }
export type { I as J }
export { type V as W, type I as K }
const x = 1
export { type V as X, x }
export class C {}
</script>
