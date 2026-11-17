<template>
  <div><div v-html="foo"></div></div>
  <div><div v-html="."></div></div>
  <div><div v-html="/**/"></div></div>
  <div><div v-html:aaa="foo"></div></div>
  <div><div v-html.aaa="foo"></div></div>
  <div><div v-html></div></div>
  <div><div v-html=""></div></div>
</template>
