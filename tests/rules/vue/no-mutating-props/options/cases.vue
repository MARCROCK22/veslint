<template>
  <div>
    <input v-model="name" />
    <input v-model="obj.a" />
    <input v-model="props.obj.a" />
    <input v-model="props.name" />
    <button @click="name = 'x'">a</button>
    <button @click="obj.a++">b</button>
    <button @click="list.push(1)">c</button>
  </div>
</template>
<script setup lang="ts">
const props = withDefaults(defineProps<{ name?: string; obj: { a: number }; list: number[] }>(), { name: 'n' })
props.name = 'y'
props.obj.a = 3
props.list.push(4)
</script>
