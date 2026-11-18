declare const Vue: any
new Vue({ watch: { a: () => {} } })
const notVue = { watch: { a: () => {} } }
