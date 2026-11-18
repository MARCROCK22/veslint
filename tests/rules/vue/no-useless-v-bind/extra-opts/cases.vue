<template>
  <div>
    <MyComp :a="'x'" v-bind:b="`y`" :c="'a\nb'" :d="'a\'b'" :e="`a\`b`" :f="'a' /* c */" :g="`${x}`" :h.prop="'z'" v-bind="'w'" />
    <MyComp :i='"q\"uote"' :j="'\\x'" :k="'é'" :l="1" :m=`'u'` :n="'A'" :o="'a\
b'" />
    <MyComp :p="'double&quot;quote'" :q='"single&apos;q"' :r="'\x41'" />
  </div>
</template>
