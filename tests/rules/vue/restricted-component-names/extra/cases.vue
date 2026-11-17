<template>
  <div>
    <MyButton />
    <my-button></my-button>
    <OtherThing>
      <svg><circle /><foreignObject /></svg>
      <Teleport /><keep-alive /><center></center><marquee />
    </OtherThing>
    <component :is="x" />
  </div>
</template>
