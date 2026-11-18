<template>
  <div>
    <MyComp>
      <div slot-scope="a" />
      <template slot-scope>{{ x }}</template>
      <span slot="n" slot-scope="b" />
      <span :slot="m" slot-scope="c" />
      <p
        slot-scope="{ d }" />
    </MyComp>
    <MyComp><template slot-scope="e" /><template slot-scope="f" /></MyComp>
    <div><span slot-scope="g" /></div>
    <MyComp slot-scope="h" />
  </div>
</template>
