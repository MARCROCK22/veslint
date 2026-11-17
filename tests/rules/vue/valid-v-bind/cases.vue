<template>
  <div><div v-bind:aaa="bbb"></div></div>
  <div><div v-bind:aaa='bbb'></div></div>
  <div><div v-bind:aaa=bbb></div></div>
  <div><div v-bind="bbb"></div></div>
  <div><div v-bind:aaa.prop='bbb'></div></div>
  <div><div v-bind:aaa.camel='bbb'></div></div>
  <div><div :aaa="bbb"></div></div>
  <div><div :aaa='bbb'></div></div>
  <div><div :aaa=bbb></div></div>
  <div><div :aaa.prop='bbb'></div></div>
  <div><div :aaa.camel='bbb'></div></div>
  <div><div :aaa.attr='bbb'></div></div>
  <div><input v-bind='$attrs' /></div>
  <div><div :foo /></div>
  <div><div v-bind:foo /></div>
  <div><MyComponent :foo="." /></div>
  <div><MyComponent :foo="/**/" /></div>
  <div><div v-bind></div></div>
  <div><div :aaa.unknown='bbb'></div></div>
  <div><MyComponent :foo="" /></div>
</template>
