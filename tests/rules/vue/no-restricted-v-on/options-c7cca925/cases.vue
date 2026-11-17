<template>
  <div>
        <div @v-on @foo.once="bar" />
        <MyButton @foo="foo" @bar="bar" />
      </div>
</template>
