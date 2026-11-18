<template>
  <div><input v-model="foo"></div>
  <div><input type="text" v-model.lazy="foo"></div>
  <div><input type="number" v-model.number="foo"></div>
  <div><input type="password" v-model.trim="foo"></div>
  <div><input type="checkbox" v-model="foo.bar"></div>
  <div><input type="radio" v-model="foo"></div>
  <div><textarea v-model="foo"></textarea></div>
  <div><select v-model="foo"></select></div>
  <div><your-component v-model="foo"></your-component></div>
  <div><div><div v-for="x in list"><input v-model="x.foo"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[x]"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[x - 1]"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[`${x}`]"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[`prefix_${x}`]"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[x ? x : '_']"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[x || '_']"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[x()]"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[/r/.match(x) ? 0 : 1]"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[typeof x]"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="foo[tag`${x}`]"></div></div></div>
  <div><input :type="a" v-model="b"></div>
  <div><input v-bind:type="a" v-model="b"></div>
  <div><MyComponent v-model:aaa="a"></MyComponent></div>
  <div><MyComponent v-model:aaa.modifier="a"></MyComponent></div>
  <div><MyComponent v-model.modifier="a"></MyComponent></div>
  <div><MyComponent v-model:aaa.modifier.modifierTwo="a"></MyComponent></div>
  <div><MyComponent v-model.modifier.modifierTwo="a"></MyComponent></div>
  <div>
        <svg>
          <MyComponent v-model="slotProps"></MyComponent>
        </svg>
      </div>
  <div><MyComponent v-model="." /></div>
  <div><MyComponent v-model="/**/" /></div>
  <div><MyComponent v-model="a as string"></MyComponent></div>
  <div><MyComponent v-model="a!"></MyComponent></div>
  <div><MyComponent v-model="a as unknown as string"></MyComponent></div>
  <div><MyComponent v-model="a!!!!"></MyComponent></div>
  <div><MyComponent v-model="(((a!) as unknown)! as string)!"></MyComponent></div>
  <div><div v-model="foo"></div></div>
  <div><input v-model:aaa="foo"></div>
  <div><input v-model.aaa="foo"></div>
  <div><input v-model></div>
  <div><input v-model="a + b"></div>
  <div><input type="file" v-model="b"></div>
  <div><div><div v-for="x in list"><input v-model="x"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="(x)"></div></div></div>
  <div><div><div v-for="x in list"><input v-model="(((x)))"></div></div></div>
  <div><div><div v-for="e in list"><input v-model="e"></div></div></div>
  <div><MyComponent v-model="" /></div>
  <div><input v-model="foo?.bar"></div>
  <div><input v-model="foo?.bar.baz"></div>
  <div><input v-model="(a?.b)?.c"></div>
  <div><input v-model="(a?.b).c"></div>
  <div><input v-model="(null).foo"></div>
  <div><input v-model="(a?.b).c.d"></div>
  <div><MyComponent v-model="a() as string"></MyComponent></div>
  <div><MyComponent v-model="a()!"></MyComponent></div>
  <div><MyComponent v-model="a() as unknown as string"></MyComponent></div>
  <div><MyComponent v-model="a()!!!!"></MyComponent></div>
  <div><MyComponent v-model="(((a()!) as unknown)! as string)!"></MyComponent></div>
</template>
