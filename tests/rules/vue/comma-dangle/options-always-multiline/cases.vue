<template>
  <p>{{ [a, b] }}</p>
  <div :a="{
    x: 1,
    y: 2
  }" />
  <div :a="[
    1,
    2,
  ]" />
  <div :a="{ x: 1, }" />
</template>
