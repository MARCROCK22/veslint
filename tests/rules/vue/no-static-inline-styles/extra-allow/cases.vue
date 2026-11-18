<template>
  <div>
    <div style="color: red" :style="{ color: 'red', 'font-size': '1px', 1: 2 }" />
    <div :style="[{ a: 1 }, , { b: 2 }]" />
    <div :style="[{ a: 1, b }, { c: 1 }]" />
    <div :style="[{ a: 1 }, x, { c: 1 }]" />
    <div :style="{ a: 1, ...rest, b: 2 }" />
    <div :style="{ a: 1, [k]: 2, b: 2 }" />
    <div :style="{ a: `x` }" />
    <div v-bind:style="{}" />
    <div :style="[]" />
    <div :[style]="{ a: 1 }" />
    <div :style="({ a: 1 })" />
  </div>
</template>
