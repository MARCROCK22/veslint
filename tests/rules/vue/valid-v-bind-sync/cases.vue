<template>
  <div><MyComponent :foo.sync="foo" /></div>
  <div><MyComponent v-bind:foo.sync="foo" /></div>
  <div><MyComponent :foo.sync="foo.bar" /></div>
  <div><MyComponent v-bind.sync="foo" /></div>
  <div><svg><MyComponent :foo.sync="foo" /></svg></div>
  <div><MyComponent :foo.sync="this.foo().bar" /></div>
  <div><svg><MyComponent :foo.sync="this.foo().bar" /></svg></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="x.foo" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x - 1]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[`${x}`]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[`prefix_${x}`]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x ? x : '_']" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x || '_']" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[x()]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[/r/.match(x) ? 0 : 1]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[typeof x]" /></div></div></div>
  <div><div><div v-for="x in list"><MyComponent :foo.sync="foo[tag`${x}`]" /></div></div></div>
  <div><MyComponent :foo="a + b" /></div>
  <div><MyComponent v-bind:foo="a + b" /></div>
  <div><MyComponent :foo.sync /></div>
  <div><MyComponent v-bind:foo.sync /></div>
  <div><MyComponent :foo.sync.unknown="foo" /></div>
  <div><MyComponent :foo.sync="." /></div>
  <div><MyComponent :foo.sync="/**/" /></div>
  <div><MyComponent :foo.sync="" /></div>
  <div>
        <table>
          <tr is="my-row"
            :some-prop.sync="somePropValue"
            :some-other-prop.sync="someOtherPropValue">
            <td></td>
          </tr>
        </table>
      </div>
  <div>
        <table>
          <tr :is="my-row"
            :some-prop.sync="somePropValue"
            :some-other-prop.sync="someOtherPropValue">
            <td></td>
          </tr>
        </table>
      </div>
  <div>
        <table>
          <tr v-bind:is="myRow"
            :some-prop.sync="somePropValue"
            :some-other-prop.sync="someOtherPropValue">
            <td></td>
          </tr>
        </table>
      </div>
  <div>
          <MyComponent :foo.sync="a + b" />
        </div>
  <div>
          <MyComponent v-bind:foo.sync="a + b" />
        </div>
  <div>
          <input :foo.sync="foo">
        </div>
  <div>
          <MyComponent :foo.sync="foo()" />
        </div>
  <div>
          <MyComponent :foo.sync="this.foo()" />
        </div>
  <div>
          <input v-bind:foo.sync="foo">
        </div>
  <div>
          <div v-for="x in list">
            <MyComponent :foo.sync="x" />
          </div>
        </div>
  <div>
          <div v-for="e in list">
            <MyComponent v-bind:foo.sync="e" />
          </div>
        </div>
  <div>
          <div v-for="e1 in list1">
            <div><div>
              <div v-for="e2 in list2">
                <MyComponent v-bind:foo.sync="e1" />
              </div>
            </div></div>
          </div>
        </div>
  <div>
          <div v-for="(e, index) in list">
            <MyComponent v-bind:foo.sync="index" />
          </div>
        </div>
  <div>
          <div :foo.sync="foo"></div>
        </div>
  <div><MyComponent v-bind.sync="foo()" /></div>
  <div><svg><MyComponent :foo.sync="foo()" /></svg></div>
  <div><MyComponent :foo.sync="foo?.bar" /></div>
  <div><MyComponent :foo.sync="foo?.bar.baz" /></div>
  <div><MyComponent :foo.sync="(a?.b)?.c" /></div>
  <div><MyComponent :foo.sync="(a?.b).c" /></div>
  <div><MyComponent :foo.sync="(null).foo" /></div>
  <div><MyComponent :foo.sync="(a?.b).c.d" /></div>
  <div><tr v-on:is="myRow" :some-prop.sync="somePropValue"></div>
  <div><tr v-bind="myRow" :some-prop.sync="somePropValue"></div>
</template>
