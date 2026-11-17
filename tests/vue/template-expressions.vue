<template>
  <div :a="x as Foo<Bar>" :b="<Baz>y" :c="z satisfies Qux" :d="a?.b?.[c]?.(d)" :e="`t${u}v${w}`">
    {{ typeof t === 'string' ? t : t! }}
    {{ (a, b) }}
    {{ a ?? b ?? c }}
    {{ /re+g/gi.test(s) | f(/x\//) | g }}
    {{ o.p | h(1, 'a|b', [c | d]) }}
    {{ arr.map((item, i) => item + i + outer).filter(function named(x) { return x > limit }) }}
    {{ new Map<string, number>() }}
    {{ fn<T>(arg) }}
    {{ async () => { await p; let q = 1; q += r; return q } }}
    {{ class K extends Base { m() { return this.f } static s = 1 } }}
    {{ ({ a, b: [c, ...d] } = src) }}
    {{ count++ }} {{ --count }} {{ total += 1 }}
    {{ 1n + 0x10 + 1e3 + 0.5 }}
    <span v-for="(item, key, index) in items" :key="item.id + key + index">{{ item }}</span>
    <span v-for="{ id, name = 'n' } of list" :title="name">{{ id }}</span>
    <span v-for="[a, , b] in pairs">{{ a + b }}</span>
    <span v-for="n in 10">{{ n }}</span>
    <span v-for="(x) in xs" :x="x"></span>
    <comp v-slot="{ item, index }: { item: Item; index: number }">{{ item }} {{ index }} {{ other }}</comp>
    <comp #header="{ title = 'default', ...rest }">{{ title }}{{ rest }}</comp>
    <comp #[dynamicSlot]="props">{{ props }}</comp>
    <template slot-scope="scope"><i>{{ scope.row }}</i></template>
    <button @click="count++" @dblclick="handler" @keyup.enter.prevent="go($event, 1)" @focus="() => focus()" @blur="async e => { await save(e) }" @input="function (e) { log(e) }" @change="a.b['c'][0]"></button>
    <button @click="a(); b(); if (c) { d() }" @mouseover="; ;" v-on="listeners" @[eventName]="onEvent"></button>
    <input v-model.trim.lazy="form.name" :value.prop="v" .text="t" :foo-bar="fb" :[`key${n}`]="dyn">
    <p v-if="ok" v-else-if="other" v-show="shown" v-html="raw" v-text="txt" v-custom:arg.mod="val" v-memo="[a, b]"></p>
    <i :class="{ active: isActive, 'text-danger': hasError }" :style="[base, override]"></i>
    <i :same-name :sameName :v-bind-ok></i>
  </div>
</template>
<script setup lang="ts">
import { ref } from 'vue'
const count = ref(0)
</script>
