<template>
  <div>
    <div v-for="(item, index) in items" :key="index" />
    <div v-for="(item, index) in items" :key="item" />
    <div v-for="({ a, b: [c, d], ...e }, i) in items" :key="i" />
    <div v-for="({ a = 1 }, i) in items" :key="i" />
    <div v-for="[x, y] in items" />
    <div v-for="(MyComp, k) in comps"><MyComp /><span><k /></span></div>
    <Comp v-slot="{ p, q }">{{ q }}</Comp>
    <Comp #default="props" />
    <Comp><template #named="{ r: { s }, t }">{{ t }}</template></Comp>
    <div v-for="(_a, _b) in items" />
    <Comp slot-scope="scope" />
    <div v-for="(v, k, i) in obj" :key="k" />
  </div>
</template>
