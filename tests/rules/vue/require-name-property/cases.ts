import { defineComponent } from 'vue'
declare const Vue: any
defineComponent({
    props: {},
})
Vue.mixin({})
Vue.component('x', { name: 'X' })
Vue.component('y', { ['name']: 'Y' })
new Vue({})
