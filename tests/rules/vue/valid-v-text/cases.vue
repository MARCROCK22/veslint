<template>
  <div><div v-text="foo"></div></div>
  <div><div v-text="." /></div>
  <div><div v-text="/**/" /></div>
  <div><div v-text:aaa="foo"></div></div>
  <div><div v-text.aaa="foo"></div></div>
  <div><div v-text></div></div>
  <div><div v-text="" /></div>
</template>
