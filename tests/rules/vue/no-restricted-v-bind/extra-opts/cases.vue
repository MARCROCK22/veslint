<template>
  <div>
    <MyComp :v-foo="a" v-bind:v-bar="b" .v-baz="c" v-bind="d" :[e]="f" :foo.prop="g" :foo.camel.sync="h" :Foo="i" />
    <div :foo="j" :bar.prop="k" />
  </div>
</template>
