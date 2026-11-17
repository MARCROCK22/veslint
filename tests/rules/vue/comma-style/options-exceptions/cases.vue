<template>
  <div :a="[a
    , b]" />
  <div :a="{x: 1
    , y: 2}" />
  <div @click="fn(a
    , b)" />
</template>
