<template>
  <div><div v-once></div></div>
  <div><div v-once:aaa></div></div>
  <div><div v-once.aaa></div></div>
  <div><div v-once="aaa"></div></div>
  <div><MyComponent v-once="." /></div>
  <div><MyComponent v-once="/**/" /></div>
  <div><MyComponent v-once="" /></div>
</template>
