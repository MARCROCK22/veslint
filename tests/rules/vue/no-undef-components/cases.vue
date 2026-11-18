<template>
  <div>
    <MyComp />
    <my-comp />
    <OtherComp />
    <TypeOnly />
    <InterfaceOnly />
    <ns.Input />
    <Undefined />
    <keep-alive /><Transition /><RouterView />
    <component is="Undefined2" />
    <component is="vue:MyComp" />
    <cases />
    <Map />
    <comment />
  </div>
</template>
<script setup lang="ts">
import MyComp from './MyComp.vue'
import type TypeOnly from './TypeOnly.vue'
import * as ns from './ns'
interface InterfaceOnly { a: number }
const otherComp = {}
</script>
