<template>
  <div><div>{{ this.foo.bar }}</div></div>
  <div><div v-for="foo in this.bar">{{ foo }}</div></div>
  <div><div v-if="this.foo">{{ this.foo }}</div></div>
  <div><div :class="this.foo">{{ this.foo }}</div></div>
  <div><div :class="{this: this.foo}">{{ this.foo }}</div></div>
  <div><div v-for="bar in this.foo" v-if="bar">{{ bar }}</div></div>
  <div><div v-if="this.foo()">{{ this.bar }}</div></div>
  <div><div v-for="x of this.xs">{{this.x}}</div></div>
  <div><div v-for="x of this.xs">{{this.x()}}</div></div>
  <div><div v-for="x of this.xs">{{this.x.y()}}</div></div>
  <div><div v-for="x of this.xs">{{this.x['foo']}}</div></div>
  <div><div v-for="x of this.xs">{{this['x']}}</div></div>
  <div>
        <div>
          <div v-for="bar in this.foo" v-if="bar">{{ bar }}</div>
          <div v-for="ssa in this.sss" v-if="ssa">
            <div v-for="ssf in ssa" v-if="ssa">{{ ssf }}</div>
          </div>
        </div>
      </div>
  <div><div>{{ this?.foo.bar }}</div></div>
  <div><div v-for="foo in this?.bar">{{ foo }}</div></div>
  <div><div v-if="this?.foo">{{ this?.foo }}</div></div>
  <div><div :class="this?.foo">{{ this?.foo }}</div></div>
  <div><div :class="{this: this?.foo}">{{ this?.foo }}</div></div>
  <div><div v-for="bar in this?.foo" v-if="bar">{{ bar }}</div></div>
  <div><div v-if="this?.foo()">{{ this?.bar }}</div></div>
  <div><div v-for="x of this?.xs">{{this.x}}</div></div>
  <div><div v-for="x of this?.xs">{{this.x()}}</div></div>
  <div><div v-for="x of this?.xs">{{this.x.y()}}</div></div>
  <div><div v-for="x of this?.xs">{{this.x['foo']}}</div></div>
  <div><div v-for="x of this?.xs">{{this['x']}}</div></div>
  <div>
        <div>
          <div v-for="bar in this?.foo" v-if="bar">{{ bar }}</div>
          <div v-for="ssa in this?.sss" v-if="ssa">
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
  <div><div>{{ foo }}</div></div>
  <div><div>{{ foo() }}</div></div>
  <div><div>{{ foo.bar() }}</div></div>
  <div><div :class="foo"></div></div>
  <div><div :class="{foo: foo}"></div></div>
  <div><div :class="{foo: foo()}"></div></div>
  <div><div v-if="foo"></div></div>
  <div><div v-for="foo in bar"></div></div>
</template>
