<template>
  <div><div><div v-for="x in list" v-if="x"></div></div></div>
  <div><div><div v-for="x in list" v-if="x.foo"></div></div></div>
  <div><div><div v-for="(x,i) in list" v-if="i%2==0"></div></div></div>
  <div><div><div v-for="{x} in list" v-if="x"></div></div></div>
  <div><div><div v-for="{x,y,z} in list" v-if="y.foo"></div></div></div>
  <div><div><div v-for="({x,y,z},i) in list" v-if="i%2==0"></div></div></div>
</template>
