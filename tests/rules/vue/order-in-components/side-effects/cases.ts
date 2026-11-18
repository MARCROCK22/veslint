import { defineComponent } from 'vue'
declare function sideEffect(): object
defineComponent({
  data: sideEffect(),
  name: 'X',
})
defineComponent({
  computed: {},
  data: { a: 1 + 2, b: [!x, typeof x, `t${x}`], c: x?.y, d: x ? 1 : 2 },
  props: {}
})
defineComponent({
  methods: {},
  ...spread,
  data: x++,
})
declare let x: any
declare const spread: object
