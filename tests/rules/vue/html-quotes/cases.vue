<template>
  <div><div class="foo"></div></div>
  <div><div :class="foo"></div></div>
  <div><div class=foo></div></div>
  <div><div class='foo'></div></div>
  <div><div :class=foo></div></div>
  <div><div :class='foo'></div></div>
  <div><div :class=foo+"bar"></div></div>
</template>
