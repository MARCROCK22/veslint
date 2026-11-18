<template>
  <div>{{ 'héllo wörld' }}</div>
  <div>&amp{{ 'x' }}</div>
  <div>&{{ '#1;' }}</div>
  <div>{{ 'a &amp; b' }}</div>
  <div>{{ 'a & b' }}</div>
  <div>{{ 'a &bsol; b' }}</div>
  <div>{{ 'a &#X5C; b' }}</div>
  <div>{{ 'a A b' }}</div>
  <div>{{ 'a \' b' }}</div>
  <div>{{ "a \" b" }}</div>
  <div>{{ `tpl` }}</div>
  <div>{{ `tp\nl` }}</div>
  <div>{{ ' lead' }}</div>
  <div>{ {{ '{' }}</div>
  <div>{{ '<b>' }}</div>
  <div>{{ 'x' /* c */ }}</div>
  <div>{{ 'a\\b' }}</div>
  <div>{{ '😀 emoji' }}</div>
  <div>{{ 1 }}</div>
  <div :a="'x'">{{ 'y' }}{{ 'z' }}</div>
</template>
