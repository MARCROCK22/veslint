<template>
  <div><div><custom data-id="foo" aria-test="bar" slot-scope="{ data }" myProp="prop"></custom></div></div>
  <div><div data-id="foo" aria-test="bar" slot-scope="{ data }"><a onClick="" my-prop="prop"></a></div></div>
  <div><my-component :[foo-bar]></my-component></div>
  <div><div><slot myProp></slot></div></div>
  <div><div><custom :attr_ff="prop"></custom></div></div>
  <div><div><custom :myName.sync="prop"></custom></div></div>
  <div><div><custom my-prop="foo"></custom></div></div>
  <div><div><custom :my-prop="prop"></custom></div></div>
  <div><div><custom v-bind:my-prop="prop"></custom></div></div>
  <div><div><custom v-model:my-prop="prop"></custom></div></div>
  <div>
          <custom data-id="foo" aria-test="bar" slot-scope="{ data }" custom-hyphen="foo" second-custom="baz" thirdCustom="bar">
            <a onClick="" my-prop="prop"></a>
          </custom>
        </div>
  <div><div><slot my-prop="foo"></slot></div></div>
  <div><div><custom :my-custom_prop="prop"></custom></div></div>
  <div><div><custom :my-age.sync="prop"></custom></div></div>
</template>
