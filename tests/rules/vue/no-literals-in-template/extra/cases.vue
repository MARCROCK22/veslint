<template>
  <div>
    <MyComp v-for="item in items" :key="item.id" :a="{ id: item.id }" :b="[1, 2]" />
    <MyComp v-for="{ id } in items" :a="() => id" :b="function () { return 1 }" />
    <MyComp #default="{ item }">
      <Child :x="{ item }" :y="{ z: 1 }" v-bind="{ a: 1 }" :[dyn]="[]" :class="{ a: true }" :style="[x]" />
    </MyComp>
    <MyComp :a="({ b: 1 } as X)" :c="[] satisfies Y" :d="a ? {} : []" />
  </div>
</template>
