<template>
  <div><MyComponent v-bind:foo='bar'/></div>
  <div><MyComponent :foo='bar'/></div>
  <div><MyComponent v-bind:[dynamicArg]='bar'/></div>
  <div><MyComponent :[dynamicArg]='bar'/></div>
  <div><MyComponent v-bind:foo.sync='bar'/></div>
  <div><MyComponent :foo.sync='bar'/></div>
  <div><MyComponent v-bind:[dynamicArg].sync='bar'/></div>
  <div><MyComponent :[dynamicArg].sync='bar'/></div>
  <div><MyComponent v-bind.sync='bar'/></div>
  <div><MyComponent :foo.sync.unknown="foo" /></div>
  <div><MyComponent :[dynamicArg].sync.unknown="foo" /></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="x.foo" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x - 1]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[`${x}`]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[`prefix_${x}`]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x ? x : '_']" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x || '_']" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x()]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[/r/.match(x) ? 0 : 1]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[typeof x]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[tag`${x}`]" /></div></div></div>
</template>
