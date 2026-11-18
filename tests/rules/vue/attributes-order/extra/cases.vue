<template>
  <div>
    <div :b="1" v-bind="obj" v-if="x" />
    <div v-bind="obj" :b="1" id="i" />
    <div v-model="m" v-bind="obj" is="c" />
    <div class="a" v-bind="obj" v-for="x in y" :key="x" />
    <div @click="f" v-bind="obj" ref="r" />
    <div :[dyn]="1" v-foo:[bar].baz="2" v-for="z in w" />
    <MyComp v-slot="s" ref="r2" v-is="'x'" />
    <div zzz="1" :yyy="2" xxx v-text="t" v-show="s" />
  </div>
</template>
