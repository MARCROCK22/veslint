<template>
  <div><div v-bind="foo"></div></div>
  <div><div foo="foo"></div></div>
  <div><div :foo="foo"></div></div>
  <div><div :v-model="foo"></div></div>
  <div><div v-bind:v-model="foo"></div></div>
</template>
