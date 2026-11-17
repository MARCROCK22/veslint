<template>
  <div><MyComponent v-model="bar"></MyComponent></div>
  <div><MyComponent v-model:foo="bar"></MyComponent></div>
  <div><MyComponent v-model:foo.trim="bar"></MyComponent></div>
</template>
