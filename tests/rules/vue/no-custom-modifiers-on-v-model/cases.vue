<template>
  <div><MyComponent v-model:propName="foo"></div>
  <div><MyComponent v-model="foo"></div>
  <div><MyComponent v-model:propName.trim="foo"></div>
  <div><MyComponent v-model.trim="foo"></div>
  <div><MyComponent v-model:propName.lazy="foo"></div>
  <div><MyComponent v-model.lazy="foo"></div>
  <div><MyComponent v-model:propName.number="foo"></div>
  <div><MyComponent v-model.number="foo"></div>
  <div><MyComponent v-model:propName.aaa="foo"></div>
  <div><MyComponent v-model.aaa="foo"></div>
</template>
