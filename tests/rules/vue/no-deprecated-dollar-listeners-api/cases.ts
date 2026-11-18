import Vue from 'vue'
Vue.component('x', { mounted() { console.log(this.$listeners) } })
