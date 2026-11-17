<template>
  <div><div :arr="myArray"></div></div>
  <div><div :obj="myObject"></div></div>
  <div><div :callback="myFunction"></div></div>
  <div><div v-bind="myProps"></div></div>
  <div><div v-bind:foo="bar"></div></div>
  <div><div v-bind:[foo]="bar"></div></div>
  <div><div v-bind:[foo].camel="bar"></div></div>
  <div><div :foo></div></div>
  <div><div :foo.camel></div></div>
  <div><div :class="['active', errorClass]"></div></div>
  <div><div :class="{ active: isActive }"></div></div>
  <div><div v-bind:class="[]"></div></div>
  <div><div :style="{ color: 'red' }"></div></div>
  <div><div :style="[baseStyles, overridingStyles]"></div></div>
  <div><div v-bind:style="[]"></div></div>
  <div>
          <template v-for="i in arr">
            <MyComponent :data="{ index: i }" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <MyComponent :data="{ val: foo }" />
            </template>
          </Child>
        </div>
  <div>
          <template v-for="i in arr">
            <MyComponent :data="[i]" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <MyComponent :data="[foo]" />
            </template>
          </Child>
        </div>
  <div>
          <template v-for="i in arr">
            <MyComponent :callback="() => someFunction(someArgs, i)" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <ChildComponent :callback="() => someFunction(someArgs, foo)" />
            </template>
          </Child>
        </div>
  <div>
          <template v-for="i in arr">
            <MyComponent :callback="function() { return someFunction(someArgs, i) }" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <ChildComponent :callback="function() { return someFunction(someArgs, foo) }" />
            </template>
          </Child>
        </div>
  <div><div :arr="[]"></div></div>
  <div><div :arr="[1,2,3]"></div></div>
  <div><div :obj="{}"></div></div>
  <div><div :obj="{name:'Tom', age: 123}"></div></div>
  <div><div :callback="() => someFunction(someArgs)"></div></div>
  <div><div :callback="function() { return 1 }"></div></div>
  <div><div :arr="[...myArray]"></div></div>
  <div><div :obj="{...myObject}"></div></div>
  <div><div v-bind="{foo: 1}"></div></div>
  <div><div v-bind:foo="{}"></div></div>
  <div><div v-bind:foo="[]"></div></div>
  <div><div v-bind:foo="() => someFunction(someArgs)"></div></div>
  <div><div v-bind:foo="function() { return 1 }"></div></div>
  <div><div v-bind:[key]="{}"></div></div>
  <div><div v-bind:[key]="[]"></div></div>
  <div><div v-bind:[key]="() => someFunction(someArgs)"></div></div>
  <div><div v-bind:[key]="function() { return 1 }"></div></div>
  <div><div :[key].camel="{}"></div></div>
  <div><div :[key].camel="[]"></div></div>
  <div><div :[key].camel="() => someFunction(someArgs)"></div></div>
  <div><div :[key].camel="function() { return 1 }"></div></div>
  <div>
          <template v-for="i in arr">
            <MyComponent :data="{ val: globalVars }" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <MyComponent :data="{ val: globalVars }" />
            </template>
          </Child>
        </div>
  <div>
          <template v-for="i in arr">
            <MyComponent :data="[globalVars]" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <MyComponent :data="[globalVars]" />
            </template>
          </Child>
        </div>
  <div>
          <template v-for="i in arr">
            <MyComponent :callback="() => someFunction(someArgs, globalVars)" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <MyComponent :callback="() => someFunction(someArgs, globalVars)" />
            </template>
          </Child>
        </div>
  <div>
          <template v-for="i in arr">
            <MyComponent :callback="function() { return someFunction(someArgs, globalVars) }" />
          </template>
        </div>
  <div>
          <Child>
            <template #default="{ foo }">
              <ChildComponent :callback="function() { return someFunction(someArgs, globalVars) }" />
            </template>
          </Child>
        </div>
</template>
