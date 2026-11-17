<template>
  <div><div :v-model="foo"></div></div>
  <div><div :bar="foo"></div></div>
  <div><div foo="foo"></div></div>
  <div><div :foo="bar" :bar="foo"></div></div>
</template>
