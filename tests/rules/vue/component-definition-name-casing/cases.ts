declare const Vue: any
declare const app: any
Vue.component('my-component', {})
app.component('MyComponent', {})
app.component(`my_component`, {})
Vue.component('foo-bar')
Vue.mixin({ name: 'my-mixin' })
new Vue({ name: 'vue-instance' })
