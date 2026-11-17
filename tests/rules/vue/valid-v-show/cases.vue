<template>
  <div><div v-show="foo"></div></div>
  <div><MyComponent v-show="." /></div>
  <div><MyComponent v-show="/**/" /></div>
  <div><div v-show:aaa="foo"></div></div>
  <div><div v-show.aaa="foo"></div></div>
  <div><div v-show></div></div>
  <div><div v-show=""></div></div>
  <div><template v-show="condition"></template></div>
</template>
