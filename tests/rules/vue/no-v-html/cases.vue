<template>
  <div></div>
  <div><div v-if="foo"></div></div>
  <div><div v-if="foo" v-bind="bar"></div></div>
  <div><div v-html="foo"></div></div>
  <div><ul v-html:aaa="userHTML"></ul></div>
  <div><section v-html/></div>
</template>
