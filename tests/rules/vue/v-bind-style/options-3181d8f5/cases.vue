<template>
  <div><div v-bind:foo="foo" /></div>
  <div><div v-bind:foo.prop="foo" /></div>
  <div><div v-bind:foo /></div>
  <div><div .foo /></div>
</template>
