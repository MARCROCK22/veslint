<template>
  <div ref="root" />
  <input ref="input" />
  <span ref="other" />
  <b ref="" />
  <i :ref="dynamic" />
  <p ref="later" />
  <p ref="root" />
</template>
<script setup lang="ts">
import { ref, shallowRef, useTemplateRef } from 'vue'
const root = ref()
const input = shallowRef<HTMLInputElement>(), extra = ref()
let other = ref(null)
const later = useTemplateRef('later')
const dynamic = ref()
function f() { const inner = ref() }
</script>
