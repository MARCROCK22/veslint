declare const Vue: any
Vue.component('a', {
  data: (vm: any) => ({ a: vm.foo, b: (this as any).foo }),
  computed: { foo() { return 1 } },
})
