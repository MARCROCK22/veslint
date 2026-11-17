<template>
  <div><div><template v-for="x in list"><Foo /></template></div></div>
  <div><div><template v-for="x in list" :key="x"><Foo /></template></div></div>
  <div><div><template v-for="x in list" :key="x.id"><Foo :key="x.id" /></template></div></div>
  <div><div><template v-for="(x, i) in list" :key="i"><Foo :key="x" /></template></div></div>
  <div><div><template v-for="(x, i) in list"><Foo :key="foo" /></template></div></div>
  <div>
        <div>
          <template v-for="x in list">
            <Foo v-if="a" :key="x" />
          </template>
        </div>
      </div>
  <div>
        <div>
          <template v-for="x in list">
            <Foo v-if="a" :key="x.key1" />
            <Foo v-else-if="a" :key="x.key2" />
            <Foo v-else :key="x.key3" />
            <Foo v-for="y in list" :key="x.key4" />
          </template>
        </div>
      </div>
  <div><div><template v-for="x in list"><Foo :key="x" /></template></div></div>
  <div><div><template v-for="x in list"><Foo :key="x.id" /></template></div></div>
  <div><div><template v-for="x in list" :key="foo"><Foo :key="x.id" /></template></div></div>
  <div><div><template v-for="x in list" :key><Foo :key="x.id" /></template></div></div>
  <div><div><template v-for="x in list" :key><div /><Foo :key="x.id" /></template></div></div>
  <div><div><template v-for="x in list" :key><Foo :key="'foo' + x.id" /><Bar :key="'bar' + x.id" /></template></div></div>
  <div>
        <div>
          <template v-for="x in list">
            <Foo v-if="a" :key="x.key1" />
            <Foo v-else-if="a" :key="x.key2" />
            <Foo v-else :key="x.key3" />
            <Foo v-for="y in list" :key="x.key4" />
            <Foo :key="x.error1" />
            <div :key="x.error2" />
            <slot :key="x.error3" ></slot>
          </template>
        </div>
      </div>
</template>
