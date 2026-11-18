<template>
  <div>
    <input v-model="name" />
    <input v-model="props.name" />
    <input v-model="obj.a" />
    <child v-bind:name.sync="name" />
    <child :name="name" />
    <button @click="name = 'x'">a</button>
    <button @click="obj.a++">b</button>
    <button @click="list.push(1)">c</button>
    <button @click="props.list.sort()">d</button>
    <button @click="delete obj.a">e</button>
    <button @click="local = 1">f</button>
    <button @click="Object.assign(obj, {})">g</button>
    <div v-for="item in list" :key="item" @click="item = 2" />
  </div>
</template>
<script setup lang="ts">
import { ref } from 'vue'
const props = defineProps<{ name: string; obj: { a: number }; list: number[]; Math: number }>()
const local = ref(0)
function mutate() {
  props.name = 'y'
  props.obj.a = 3
  props.list.push(4)
  props['obj'].a++
  delete props.obj.a
  props?.obj.a
  const { name } = props
  console.log(name, local)
}
mutate()
</script>
