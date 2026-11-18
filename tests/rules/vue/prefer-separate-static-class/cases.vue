<template>
  <div><div class="static-class" /></div>
  <div><div :class="dynamicClass" /></div>
  <div><div :class="`dynamic-class-${foo}`" /></div>
  <div><div :class="`${foo}-dynamic-class`" /></div>
  <div><div :class="'dynamic-class-' + foo" /></div>
  <div><div class="static-class" :class="dynamicClass" /></div>
  <div><div class="static-class" :class="[dynamicClass]" /></div>
  <div><div class="static-class" :class="{'dynamic-class': foo}" /></div>
  <div><div class="static-class" :class="{foo, [computedName]: true}" /></div>
  <div><div class="static-class" :class="[dynamicClass, {'dynamic-class': foo}]" /></div>
  <div><div :class.attr="'static-class'" /></div>
  <div><div v-bind:class.attr="'static-class'" /></div>
  <div><MyComponent :class.attr="['static-class', dynamicClass]" /></div>
  <div><div :class.attr="{'static-class': true, foo}" /></div>
  <div><div :class.attr="`static-class ${foo}`" /></div>
  <div><div :class.prop="'static-class'" /></div>
  <div><div .class="'static-class'" /></div>
  <div><div :class.camel="'static-class'" /></div>
  <div><div v-bind:class="'static-class'" /></div>
  <div><div :class="'static-class'" /></div>
  <div><div :class="`static-class`" /></div>
  <div><div :class="`form-item input ${isDisabled ? 'disabled' : ''}`" /></div>
  <div><div :class="`${dynamicClass} static-class`" /></div>
  <div><div :class="`${start} static-class ${end}`" /></div>
  <div><div :class='"static-class"' /></div>
  <div><div :class="['static-class']" /></div>
  <div><div :class="{'static-class': true}" /></div>
  <div><div :class="{foo: true}" /></div>
  <div><div :class="{['static-class']: true}" /></div>
  <div><div :class="['static-class', dynamicClass]" /></div>
  <div><div :class="[dynamicClass, otherDynamicClass, 'static-class']" /></div>
  <div><div :class="{'static-class': true, 'dynamic-class': foo}" /></div>
  <div><div :class="[{'dynamic-class': foo, 'static-class': true}]" /></div>
  <div><div :class="[dynamicClass, {staticClass: true}]" /></div>
  <div>
          <div
            class="other-class"
            other-attribute
            :class="[
              {'dynamic-class-a': foo, 'static-class': true},
              dynamicClassB,
            ]" />
        </div>
  <div>
          <div
            class="other-class-a other-class-b"
            other-attribute
            :class="[
              'static-class-a',
              {'static-class-b': true, 'dynamic-class-a': foo},
              dynamicClassB,
            ]" />
        </div>
</template>
