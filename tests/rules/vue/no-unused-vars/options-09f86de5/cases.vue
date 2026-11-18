<template>
  <div><div v-for="_ in foo" ></div></div>
  <div><div v-for="x in items">{{value | x}}</div></div>
  <div><div v-for="(a, _i) in foo" ></div></div>
</template>
