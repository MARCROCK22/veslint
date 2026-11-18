<template>
  <div :class="foo">{{ props.bar }} {{ props.missing }} {{ undef1 }} {{ undef1 }} {{ Math.max(1, 2) }}</div>
  <input v-model="title" />
  <span>{{ $attrs }} {{ local }} {{ undef2.deep }}</span>
  <i v-for="x in list" :key="x">{{ x }} {{ undef3 }}</i>
</template>
<script setup lang="ts">
const props = defineProps<{ foo: string; bar: number; list: number[] }>()
const title = defineModel<string>('title')
const local = 1
const { foo: renamed, nope } = props
console.log(renamed, nope, title)
</script>
<style>
.a { color: v-bind(styleVar); width: v-bind(local); }
</style>
