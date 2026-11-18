<template>
  <div :class="this.cls" :[this.arg]="this.val" :foo @click="this.handle($event)">
    {{ this.a }} {{ this?.b }} {{ this['c'] }} {{ this[`d`] }} {{ this['foo-bar'] }} {{ this[0] }} {{ this['0a'] }}
    {{ this.class }} {{ this.$data }} {{ this }} {{ x[this] }} {{ this.e.f }} {{ this['$g'] }} {{ this.h_i }}
    <div v-for="item in this.items" :key="item.id">
      {{ this.item }} {{ item }} {{ this.other }}
      <Comp v-slot="{ slotProp }">{{ this.slotProp }} {{ slotProp }} {{ this.item }}</Comp>
    </div>
    <div v-for="(val, idx) of list">{{ val + idx + other }}</div>
    {{ this.item }}
    <input v-model="this.model" />
    <p v-text="(this as any).t" />
  </div>
</template>
