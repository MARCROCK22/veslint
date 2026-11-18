<template>
  <div>
    <div class=a />
    <div class="  a   b a  c b " />
    <div class="a	a" :class="`b b ${c} a a`" />
    <div :class="`x ${y ? 'x z' : 'z'} x`" />
    <div :class="'p' + ' p ' + q + 'p'" />
    <div :class="[{ 'k': a, k: b, 'k': c }, 'k']" />
    <div :class="a && 'm' || 'm'" />
    <div :class="['n', ['n', 'o'], cond ? 'o' : 'n']" />
    <div :class="'r r'" class="r s s" />
    <div v-foo:class="'t t'" />
    <div :class="'u' as string" />
    <div :class.prop="'v v'" class="v" />
    <div :class="['w', ...ws, 'w']" />
    <div class="a b" :class="[`a`, 'b b', c ? 'a' : d]" />
  </div>
</template>
