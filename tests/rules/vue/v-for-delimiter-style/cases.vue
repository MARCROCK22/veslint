<template>
  <div><div v-for="x in xs"></div></div>
  <div><div v-for="x    in xs"></div></div>
  <div><div v-for="x in    xs"></div></div>
  <div><div v-for="x    in    xs"></div></div>
  <div><div v-for="(x,) in xs"></div></div>
  <div><div v-for="(value, key, index) in xs"></div></div>
  <div><div v-for="{ x, y } in xs"></div></div>
  <div><div v-for="x of xs"></div></div>
  <div><div v-for="(x, index) of xs"></div></div>
  <div><div v-for="x    of xs"></div></div>
  <div><div v-for="x of    xs"></div></div>
  <div><div v-for="x    of    xs"></div></div>
</template>
