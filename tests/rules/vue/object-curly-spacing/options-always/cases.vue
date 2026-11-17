<template>
  <p>{{ {a: 1} }}</p>
  <div :a="{b}" />
  <div :a="{ c: { d: 1 }}" />
</template>
