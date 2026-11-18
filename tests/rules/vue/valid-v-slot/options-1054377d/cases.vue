<template>
  <div>
          <MyComponent>
            <template v-slot:foo.bar></template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot:foo></template>
            <template v-slot:foo.bar></template>
            <template v-slot:foo.baz></template>
            <template v-slot:foo.bar.baz></template>
          </MyComponent>
        </div>
</template>
