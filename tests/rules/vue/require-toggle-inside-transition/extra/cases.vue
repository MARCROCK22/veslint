<template>
  <div>
    <transition><div /><span v-if="x" /></transition>
    <transition>
      <!-- comment -->
      text
      <div />
    </transition>
    <Transition><div /></Transition>
    <transition :appear="false"><div /></transition>
    <transition :appear="0"><div /></transition>
    <transition :appear><div /></transition>
    <transition v-bind:appear="true"><div /></transition>
    <transition><slot /></transition>
    <transition><MyComp /></transition>
    <transition><div :key="k" /></transition>
    <transition><div v-show /></transition>
    <transition><svg /></transition>
    <transition><template v-if="a"><div /></template></transition>
    <transition><div is="x" /></transition>
  </div>
</template>
