<template>
  <p>{{ (a) }}</p>
  <div :a="(a * b) + c" />
  <div @click="(function () {})()" />
</template>
