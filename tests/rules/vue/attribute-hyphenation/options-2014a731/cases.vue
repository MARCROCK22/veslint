<template>
  <div><div><custom data-id="foo" aria-test="bar" slot-scope="{ data }" my-prop="prop"></custom></div></div>
  <div><div><custom :my-prop="prop" v-model:foo-bar="fooBar"></custom></div></div>
  <div><my-component :[fooBar]></my-component></div>
  <div><div><slot my-prop></slot></div></div>
  <div><div><custom :attr_ff="prop"></custom></div></div>
  <div><div><custom :my-name.sync="prop"></custom></div></div>
  <div><div><custom MyProp="Bar"></custom></div></div>
  <div><div><custom :MyProp="prop"></custom></div></div>
  <div><div><custom v-bind:MyProp="prop"></custom></div></div>
  <div><div><custom v-model:myProp="prop"></custom></div></div>
  <div><div><custom v-model:MyProp="prop"></custom></div></div>
  <div><div><slot MyProp="Bar"></slot></div></div>
  <div><div><custom :attr_Gg="prop"></custom></div></div>
  <div><div><custom :Attr_Hh="prop"></custom></div></div>
  <div><div><custom :_attr_Jj="prop"></custom></div></div>
  <div><div><custom :_attrKk="prop"></custom></div></div>
  <div><div><custom :_AttrLl="prop"></custom></div></div>
  <div><div><custom :myAge.sync="prop"></custom></div></div>
</template>
