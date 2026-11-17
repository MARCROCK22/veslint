declare function require(x: string): any
const { defineComponent } = require('vue')
const { createApp } = require('not-vue')
defineComponent({ a: 1 })
createApp({ b: 1 })
