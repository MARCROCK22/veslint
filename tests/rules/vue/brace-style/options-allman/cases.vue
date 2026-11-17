<template>
  <div @click="if (a) {
    b()
  }" />
  <div @click="() => { a() }" />
</template>
