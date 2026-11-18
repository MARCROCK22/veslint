declare const Vue: any
Vue.component('a', {
  render: function () {
    return
  },
})
Vue.component('b', {
  render: () => {},
})
Vue.component('c', {
  render() {
    const f = () => {}
    f()
  },
})
Vue.component('d', {
  render: (h: any) => h('div'),
})
Vue.component('e', {
  render(h: any) {
    switch (h.x) {
      case 1:
        return h('a')
      default:
        return h('b')
    }
  },
})
type Kind = 'a' | 'b'
declare const kind: Kind
Vue.component('f', {
  render(h: any) {
    switch (kind) {
      case 'a':
        return h('a')
      case 'b':
        return h('b')
    }
  },
})
Vue.component('g', {
  render(h: any) {
    switch (kind) {
      case 'a':
        return h('a')
    }
  },
})
const notComponent = {
  render() {},
}
