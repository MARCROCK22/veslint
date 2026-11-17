<template>
  <div><div v-on:click="foo"></div></div>
  <div><div @click="foo"></div></div>
  <div><div @click.prevent.ctrl.left="foo"></div></div>
  <div><div @keydown.27="foo"></div></div>
  <div><div @keydown.enter="foo"></div></div>
  <div><div @keydown.arrow-down="foo"></div></div>
  <div><div @keydown.esc="foo"></div></div>
  <div><div @keydown.a="foo"></div></div>
  <div><div @keydown.b="foo"></div></div>
  <div><div @keydown.a.b.c="foo"></div></div>
  <div><el-from @submit.native.prevent></el-form></div>
  <div><div v-on:click.prevent></div></div>
  <div><div v-on:click.native.stop></div></div>
  <div><div v-on="$listeners"></div></div>
  <div><div v-on="{a, b, c: d}"></div></div>
  <div><MyComponent v-on:keydown="." /></div>
  <div><MyComponent v-on:keydown="/**/" /></div>
  <div><MyComponent v-on:keydown=/**/ /></div>
  <div><MyComponent v-on:keydown.stop="/**/" /></div>
  <div><MyComponent v-on:keydown.stop=/**/ /></div>
  <div><MyComponent v-on:keydown.stop="" /></div>
  <div><div v-on:click.aaa="foo"></div></div>
  <div><div v-on:click></div></div>
  <div><div @click></div></div>
  <div><div @click="const"></div></div>
  <div><div @click="delete"></div></div>
  <div><MyComponent v-on:keydown="" /></div>
</template>
