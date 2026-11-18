import { defineComponent as dc, createApp } from 'vue'
import { defineComponent } from 'other'
declare const Vue: any
declare const app: any
// @vue/component
const marked = { data() { return {} } }
/* @vue/component */

const notMarked = {}
defineComponent({ a: 1 })
dc({ b: 1 })
createApp({ c: 1 })
Vue.component('x', { d: 1 } as any)
new Vue({ e: 1 } as any)
app.mixin({ f: 1 })
app.component({ g: 1 })
Vue.extend({ h: 1 })
app.extend({ i: 1 })
defineNuxtComponent({ j: 1 })
declare function defineNuxtComponent(x: any): any
