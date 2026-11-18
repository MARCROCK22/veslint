<template>
  <div>
    <div :class="[['a'], b]" />
    <div :class="[b, ['a']]" />
    <div :class="[b, 'a', c]" />
    <div :class="[b, 'a', ]" />
    <div :class="{ ['x']: true, [`y`]: true, [z]: true, w: false, 'v-1': true, u: 1 }" />
    <div class="first" :class="['a b', `c`, `  d  ${e}  f  `]" />
    <div :class.camel="'q'" :class.prop="'r'" :class.attr="'s'" />
    <div v-bind:class="`p`" class="" />
    <div :class="[...list, 'm', /* c */ 'n']" />
    <div :[dyn]="'x'" :class />
    <div :class="cond ? 'a' : 'b'" />
    <div :class="{ a: true }" class="k" />
  </div>
</template>
