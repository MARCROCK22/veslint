<template>
  <div><div><div v-for="x in list"></div></div></div>
  <div><div><div v-for="x of list"></div></div></div>
  <div><div><div v-for="(x, i, k) in list"></div></div></div>
  <div><div><div v-for="(x, i, k) of list"></div></div></div>
  <div><div><div v-for="({id, name}, i, k) of list"></div></div></div>
  <div><div><div v-for="([id, name], i, k) of list"></div></div></div>
  <div><div><your-component v-for="x in list" :key="x.id"></your-component></div></div>
  <div><div><div is="your-component" v-for="x in list" :key="x.id"></div></div></div>
  <div><div><div :is="your-component" v-for="x in list" :key="x.id"></div></div></div>
  <div><div><template v-for="x in list"><custom-component :key="x"></custom-component></template></div></div>
  <div><div><template v-for="x in list"><div :key="x"></div></template></div></div>
  <div><div><template v-for="x in list"><div></div></template></div></div>
  <div><template v-for="x of list"><slot name="item" /></template></div>
  <div><template v-for="x of list">foo<div></div></template></div>
  <div><div><template v-for="x of list"><div v-for="foo of x" :key="foo"></div></template></div></div>
  <div>
          <template v-for="x in xs">
            <template v-for="y in x.ys">
              <li v-for="z in y.zs" :key="z.id">
                123
              </li>
            </template>
          </template>
        </div>
  <div>
          <template v-for="x in xs">
            <template v-for="y in ys">
              <li v-for="z in zs" :key="x.id + y.id + z.id">
                123
              </li>
            </template>
          </template>
        </div>
  <div><div><template v-for="x in list" v-bind:key="x"><div /></template></div></div>
  <div><div><template v-for="x in list" v-bind:key="x"><MyComp /></template></div></div>
  <div><div><template v-for="x in list" :key="x"><div /></template></div></div>
  <div><div><template v-for="x in list" :key="x"><MyComp /></template></div></div>
  <div><div><template v-for="x in list" :key="x.id"><div /></template></div></div>
  <div><div><template v-for="x in list" :key="x.id"><MyComp /></template></div></div>
  <div><div><template v-for="(x, i) in list" :key="i"><div /></template></div></div>
  <div><div><template v-for="(x, i) in list" :key="i"><MyComp /></template></div></div>
  <div><div><template v-for="x in list" :key="x"><custom-component></custom-component></template></div></div>
  <div><div><slot v-for="x in list" :key="x"><div /></slot></div></div>
  <div><div><slot v-for="x in list" :key="x"><MyComp /></slot></div></div>
  <div><div v-for="."></div></div>
  <div><div><template v-for="xin list"><div></div></template></div></div>
  <div><div v-for="/**/"></div></div>
  <div><div><div v-for:aaa="x in list"></div></div></div>
  <div><div><div v-for.aaa="x in list"></div></div></div>
  <div><div><div v-for></div></div></div>
  <div><div><div v-for="(,a,b) in list"></div></div></div>
  <div><div><div v-for="(a,,b) in list"></div></div></div>
  <div><div><div v-for="(a,b,,) in list"></div></div></div>
  <div><div><div v-for="(a,{b,c}) in list"></div></div></div>
  <div><div><div v-for="(a,b,{c,d}) in list"></div></div></div>
  <div><div><your-component v-for="x in list"></your-component></div></div>
  <div><div><div is="your-component" v-for="x in list"></div></div></div>
  <div><div><div :is="your-component" v-for="x in list"></div></div></div>
  <div><div><div v-bind:is="your-component" v-for="x in list"></div></div></div>
  <div><div><div v-for="x in list" :key="100"></div></div></div>
  <div><div><custom-component v-for="x in list" :key="100"></custom-component></div></div>
  <div><div><div v-for="x in list" :key="foo"></div></div></div>
  <div><div><custom-component v-for="x in list" :key="foo"></custom-component></div></div>
  <div><div><div v-for="(item, index) in suggestions" :key></div></div></div>
  <div><div><template v-for="x of list"><div v-for="foo of y" :key="foo"></div></template></div></div>
  <div>
          <template v-for="x in xs">
            <template v-for="y in a.ys">
              <li v-for="z in y.zs" :key="z.id">
                123
              </li>
            </template>
          </template>
        </div>
  <div>
          <template v-for="x in xs">
            <template v-for="y in x.ys">
              <li v-for="z in a.zs" :key="z.id">
                123
              </li>
            </template>
          </template>
        </div>
  <div>
          <template v-for="x in xs">
            <template v-for="y in x.ys">
              <li v-for="z in x.zs" :key="z.id">
                123
              </li>
            </template>
          </template>
        </div>
  <div><div v-for=""></div></div>
</template>
