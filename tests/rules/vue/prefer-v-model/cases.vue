<template>
  <div><my-component v-model="foo" /></div>
  <div><my-component v-model:foo="bar" /></div>
  <div><my-component :foo="bar" @update:foo="baz = $event" /></div>
  <div><my-component :foo="bar" @update:foo="updateFoo($event)" /></div>
  <div><my-component :foo="bar" @update:foo="(val) => updateFoo(val)" /></div>
  <div><my-component :foo="bar" /></div>
  <div><my-component @update:foo="bar = $event" /></div>
  <div><input :value="bar" @update:value="bar = $event" /></div>
  <div><my-component :foo="bar" @update:foo.once="bar = $event" /></div>
  <div><my-component :foo.sync="bar" @update:foo="bar = $event" /></div>
  <div><my-component :foo="bar" @update:foo="bar = $event; doSomething()" /></div>
  <div><my-component :foo="bar" @update:foo="bar += $event" /></div>
  <div><my-component :foo="bar" @update:foo="(val) => { bar = val; doSomething() }" /></div>
  <div><my-component :foo="bar" @update:foo="(val, extra) => bar = val" /></div>
  <div><my-component :[prop]="bar" @update:foo="bar = $event" /></div>
  <div><my-component :modelValue="foo" @update:modelValue="foo = $event" /></div>
  <div><my-component :model-value="foo" @update:model-value="foo = $event" /></div>
  <div>
          <my-component
            :foo="bar"
            bar
            @update:foo="bar = $event"
          />
        </div>
  <div><my-component v-bind:foo='bar["baz"]' v-on:update:foo='bar["baz"] = $event' /></div>
  <div><my-component :foo="bar" @update:foo="(val) => bar = val" /></div>
  <div><my-component :foo="obj.bar" @update:foo="obj.bar = $event" /></div>
  <div><my-component :foo="obj.bar" @update:foo="(val) => obj.bar = val" /></div>
  <div><my-component :foo="a" @update:foo="a = $event" :bar="b" @update:bar="b = $event" /></div>
</template>
