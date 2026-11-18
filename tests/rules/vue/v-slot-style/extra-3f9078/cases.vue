<template>
  <div>
    <MyComp v-slot="a"><template #named>x</template><template v-slot:other="b">y</template></MyComp>
    <MyComp #default="a" />
    <MyComp v-slot:default="a" />
    <MyComp><template v-slot>x</template><template #default>y</template><template v-slot:default>z</template></MyComp>
    <MyComp><template #[dyn]>x</template><template v-slot:[dyn2]="p">y</template></MyComp>
  </div>
</template>
