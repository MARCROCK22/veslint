<template>
  <div>
        <div :v-on :foo.sync />
        <MyButton :foo="foo" :bar="bar" />
      </div>
</template>
