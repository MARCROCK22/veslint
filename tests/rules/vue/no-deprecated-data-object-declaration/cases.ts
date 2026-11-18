declare const Vue: any
new Vue({
  data: {
    foo: 1,
  },
})
Vue.component('a', { data: (({ a: 1 })) })
Vue.component('b', { data: function () { return {} } })
Vue.mixin({ data: [] })
