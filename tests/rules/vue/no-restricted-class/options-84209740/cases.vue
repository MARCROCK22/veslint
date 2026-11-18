<template>
  <div><div class="allowed"">Content</div></div>
  <div><div :class="'allowed' + forbidden">Content</div></div>
  <div><div @class="forbidden">Content</div></div>
  <div><div :class="'' + {forbidden: true}">Content</div></div>
  <div><div class="forbidden allowed" /></div>
  <div><div :class="'forbidden' + ' ' + 'allowed' + someVar" /></div>
  <div><div :class="{'forbidden': someBool, someVar: true}" /></div>
  <div><div :class="{forbidden: someBool}" /></div>
  <div><div :class="`forbidden ${someVar}`" /></div>
  <div><div :class="'forbidden'" /></div>
  <div><div :class="['forbidden', 'allowed']" /></div>
  <div><div :class="['allowed forbidden', someString]" /></div>
</template>
