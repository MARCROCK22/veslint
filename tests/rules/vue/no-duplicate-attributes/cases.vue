<template>
  <div><div><div foo :bar baz></div></div></div>
  <div><div><div @click="foo" @click="bar"></div></div></div>
  <div><div><div style :style></div></div></div>
  <div><div><div class :class></div></div></div>
  <div><my-component foo :[foo]></my-component></div>
  <div><my-component :foo :[foo]></my-component></div>
  <div><div><div foo v-bind:foo></div></div></div>
  <div><div><div foo :foo></div></div></div>
</template>
