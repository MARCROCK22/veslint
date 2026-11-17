<template>
  <div>
    <div v-html="a">  </div>
    <div v-html="a"><!-- c --></div>
    <div v-text="a">
      text {{ b }}
      <span />
      <!-- d -->
    </div>
    <div v-text="a" />
    <div v-html:arg.mod="a">x</div>
    <div v-custom="a">x</div>
    <div v-show="a">x</div>
  </div>
</template>
