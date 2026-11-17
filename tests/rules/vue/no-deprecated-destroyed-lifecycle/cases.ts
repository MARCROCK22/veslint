declare const Vue: any
Vue.component('a', {
  ['destroyed']() {},
  ['before' + 'Destroy']() {},
  'beforeDestroy': () => {},
})
Vue.component('b', {
  [`destroyed`]: function () {},
  beforeDestroy: 1,
})
