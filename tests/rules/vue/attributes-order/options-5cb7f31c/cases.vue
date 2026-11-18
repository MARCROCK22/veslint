<template>
  <div><div ref="foo" v-slot="{ qux }" bar="baz"></div></div>
  <div><div bar="baz" ref="foo" v-slot="{ qux }"></div></div>
</template>
