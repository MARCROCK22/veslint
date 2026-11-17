<template>
  <div>
    <MyComp>
      <div slot="a" />
      <div slot="a" />
      <template slot="b" slot-scope="{ x }">{{ x }}</template>
      <span v-for="i in list" :slot="i" :key="i" />
      <span v-for="j in list" :slot="'n' + j" :key="j" />
      <p :slot="name" scope="s" />
      <p :slot />
      <p slot="with space" />
      <p slot="" />
      <p slot />
      <p v-if="c" slot="d" /><p v-else slot="d" />
    </MyComp>
    <div><span slot="e" /></div>
    <component :is="x"><span slot="f" /></component>
    <my-comp><span slot="g" /></my-comp>
    <OtherComp><span slot="h" /></OtherComp>
  </div>
</template>
