declare const Vue: any
Vue.component('a', {
  beforeRouteEnter: function () {
    if (this.x) {
      this.y()
    }
  },
})
Vue.component('b', {
  beforeRouteEnter: () => {
    this
  },
})
