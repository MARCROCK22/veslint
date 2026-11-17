<template>
  <div><div><div v-if="foo"></div></div></div>
  <div><div v-if="."></div></div>
  <div><div v-if="/**/"></div></div>
  <div><div><div v-if="foo" v-else></div></div></div>
  <div><div><div v-if="foo" v-else-if="bar"></div></div></div>
  <div><div><div v-if:aaa="foo"></div></div></div>
  <div><div><div v-if.aaa="foo"></div></div></div>
  <div><div><div v-if></div></div></div>
  <div><div><div v-if=""></div></div></div>
</template>
