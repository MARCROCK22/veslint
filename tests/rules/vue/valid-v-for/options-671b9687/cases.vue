<template>
  <div><div><div v-for="(,a) in list"></div></div></div>
  <div><div><div v-for="(,a,b) in list"></div></div></div>
  <div><div><div v-for="(a,,b) in list"></div></div></div>
  <div><div><div v-for="(a,b,,) in list"></div></div></div>
</template>
