<template>
  <div><div v-is="foo" /></div>
  <div><div v-bind:foo="foo" /></div>
  <div><div v-is="'foo'" /></div>
  <div><div v-is="." /></div>
  <div><div v-is="/**/" /></div>
  <div><div v-is:a="foo" /></div>
  <div><div v-is.a="foo" /></div>
  <div><div v-is /></div>
  <div><div v-is="" /></div>
  <div><MyComponent v-is="foo" /></div>
</template>
