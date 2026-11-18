<template>
  <div>
    <the-component />
    <TheComponent></TheComponent>
    <the-component>x</the-component>
    <other-thing />
    <imported-comp></imported-comp>
    <typed-only />
    <ns-comp.Input />
    <svg><the-component /></svg>
    <slot /><template v-if="a" /><component is="x" />
  </div>
</template>
<script setup lang="ts">
import ImportedComp from './a.vue'
import type TypedOnly from './b.vue'
import * as NsComp from './c'
const a = 1
</script>
<script lang="ts">
export default { components: { TheComponent: {} } }
</script>
