<template>
  <div><div v-bind="foo"></div></div>
  <div><div :foo="foo"></div></div>
  <div><div :foo.prop="foo"></div></div>
  <div><div .foo="foo"></div></div>
  <div><div v-bind:foo="foo"></div></div>
</template>
