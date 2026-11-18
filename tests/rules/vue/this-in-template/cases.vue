<template>
  <div></div>
  <div><div></div></div>
  <div><div>{{ foo.bar }}</div></div>
  <div><div v-for="foo in bar">{{ foo }}</div></div>
  <div><div v-if="foo">{{ foo }}</div></div>
  <div><div :class="foo">{{ foo }}</div></div>
  <div><div :class="{this: foo}">{{ foo }}</div></div>
  <div><div v-for="bar in foo" v-if="bar">{{ bar }}</div></div>
  <div><div v-if="foo()">{{ bar }}</div></div>
  <div><div v-for="x of xs">{{this.x}}</div></div>
  <div><div v-for="x of xs">{{this.x()}}</div></div>
  <div><div v-for="x of xs">{{this.x.y()}}</div></div>
  <div><div v-for="x of xs">{{this.x['foo']}}</div></div>
  <div><div v-for="x of xs">{{this['x']}}</div></div>
  <div>
        <div>
          <div v-for="bar in foo" v-if="bar">{{ bar }}</div>
          <div v-for="ssa in sss" v-if="ssa">
            <div v-for="ssf in ssa" v-if="ssa">{{ ssf }}</div>
          </div>
        </div>
      </div>
  <div><div :parent="this"></div></div>
  <div><div>{{ this.class }}</div></div>
  <div><div>{{ this['0'] }}</div></div>
  <div><div>{{ this['this'] }}</div></div>
  <div><div>{{ this['foo bar'] }}</div></div>
  <div><div>{{ }}</div></div>
  <div><div v-on:[x]="1"></div></div>
  <div><div>{{ this.foo }}</div></div>
  <div><div>{{ this.foo() }}</div></div>
  <div><div>{{ this.foo.bar() }}</div></div>
  <div><div :class="this.foo"></div></div>
  <div><div :class="{foo: this.foo}"></div></div>
  <div><div :class="{foo: this.foo()}"></div></div>
  <div><div v-if="this.foo"></div></div>
  <div><div v-for="foo in this.bar"></div></div>
  <div><div>{{ this?.foo }}</div></div>
  <div><div>{{ this?.foo() }}</div></div>
  <div><div>{{ this?.foo.bar() }}</div></div>
  <div><div :class="this?.foo"></div></div>
  <div><div :class="{foo: this?.foo}"></div></div>
  <div><div :class="{foo: this?.foo()}"></div></div>
  <div><div v-if="this?.foo"></div></div>
  <div><div v-for="foo in this?.bar"></div></div>
  <div><div>{{ this['xs'] }}</div></div>
  <div><div>{{ this['xs0AZ_foo'] }}</div></div>
</template>
