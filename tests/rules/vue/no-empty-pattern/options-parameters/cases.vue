<template>
  <div @click="({}) => 1" />
  <div @click="function ({}) { return 1 }" />
  <div @click="const {} = $event" />
  <Comp v-slot="{}">x</Comp>
  <Comp v-slot="{ a: {} }">x</Comp>
</template>
