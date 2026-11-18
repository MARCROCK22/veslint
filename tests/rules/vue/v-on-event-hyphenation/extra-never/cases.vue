<template>
  <div>
    <MyComp @myEvent="a" v-on:fooBar.once="b" @my_event="c" @my-event="d" @[dyn]="e" @update:modelValue="f" @UPPER="g" />
    <div @myEvent="h" />
    <OtherComp @customEvent="i" @custom-event="j" />
  </div>
</template>
