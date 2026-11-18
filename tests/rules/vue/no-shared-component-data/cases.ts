declare const Vue: any
Vue.component('a', {
  data: {
    foo: 1,
  },
})
Vue.component('b', {
  data: ((({ foo: 1 }))),
})
Vue.component('c', {
  data() {
    return { foo: 1 }
  },
})
Vue.component('d', { data: () => ({}) })
Vue.component('e', { data: shared })
new Vue({ data: { x: 1 } })
declare const shared: any
