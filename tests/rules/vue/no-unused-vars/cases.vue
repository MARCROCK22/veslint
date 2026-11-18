<template>
  <div><ol v-for="i in 5"><li>{{i}}</li></ol></div>
  <div><ol v-for="i in 5"><li :prop="i"></li></ol></div>
  <div><ol v-for="i in data"><li v-for="f in i">{{ f.bar.baz }}</li></ol></div>
  <div><template scope="props">{{props}}</template></div>
  <div><template scope="props"><span v-if="props"></span></template></div>
  <div><div v-for="(item, key) in items" :key="key">{{item.name}}</div></div>
  <div><div v-for="(v, i, c) in foo">{{c}}</div></div>
  <div><div v-for="x in foo">{{value | f(x)}}</div></div>
  <div><div v-for="x in foo" :[x]></div></div>
  <div><my-component v-slot="{ Comp }"><Comp /></my-component></div>
  <div><my-component v-slot="{ Comp }"><Comp>content</Comp></my-component></div>
  <div><my-component v-slot="{ Iteration }"><div><Iteration v-for="i in items" :key="i" /></div></my-component></div>
  <div><my-component #default="{ Comp }"><Comp /></my-component></div>
  <div><my-component #wrapper="{ items, Iteration }"><Iteration v-for="(key, index) in items" :key="key" :index="index" /></my-component></div>
  <div><my-component v-slot="{ Comp }"><component :is="Comp" /></my-component></div>
  <div><my-component v-slot="{ Comp, data }"><Comp>{{ data }}</Comp></my-component></div>
  <div><my-component v-slot="{ Comp }"><div><span><Comp /></span></div></my-component></div>
  <div><ol v-for="i in 5"><li></li></ol></div>
  <div><template scope="props"></template></div>
  <div><span slot-scope="props"></span></div>
  <div><span><template scope="props"></template></span></div>
  <div><div v-for="i in 5"><comp v-for="j in 10">{{i}}{{i}}</comp></div></div>
  <div><ol v-for="i in data"><li v-for="f in i"></li></ol></div>
  <div><div v-for="(a, b, c) in foo"></div></div>
  <div><div v-for="(a, b, c) in foo">{{a}}</div></div>
  <div><div v-for="(a, b, c) in foo">{{b}}</div></div>
  <div><div v-for="(item, key) in items" :key="item.id">{{item.name}}</div></div>
  <div><div v-for="_i in foo" ></div></div>
  <div><my-component v-slot="a" >{{d}}</my-component></div>
  <div><my-component v-for="i in foo" v-slot="a" >{{a}}</my-component></div>
  <div><my-component v-for="i in foo" v-slot="a" >{{i}}</my-component></div>
  <div><div v-for="({a, b}, [c, d], e, f) in foo" >{{f}}</div></div>
  <div><div v-for="({a, b}, c, [d], e, f) in foo" >{{f}}</div></div>
  <div><my-component v-slot="{a, b, c, d}" >{{d}}</my-component></div>
  <div><div v-for="({a, b: bar}, c = 1, [d], e, f) in foo" >{{f}}</div></div>
  <div><my-component><template #a="{ Comp }"></template><template #b><Comp /></template></my-component></div>
  <div><my-component v-slot="{ Comp }"><other-component v-slot="props"><Comp /></other-component></my-component></div>
</template>
