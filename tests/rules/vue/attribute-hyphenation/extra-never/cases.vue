<template>
  <div>
    <MyComp myProp="a" :myProp2="b" v-model:myModel="c" v-bind:fooBar.sync="d" my_prop="e" @myEvent="f" :[dyn]="g" MyUpper="h" dataFoo="i" data-Foo="j" />
    <slot myName="k" my-name="l" />
    <div myProp="m" />
    <svg><circle viewBox="0 0 1 1" /></svg>
    <MyComp viewBox="1" xmlns:xlink="2" class="x" fooBAR="y" :foo-bar.camel="z" />
    <component is="x" someAttr="1" />
  </div>
</template>
