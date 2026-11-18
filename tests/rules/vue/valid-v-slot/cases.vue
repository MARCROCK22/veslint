<template>
  <div>
      <MyComponent v-slot="{data}">{{data}}</MyComponent>
    </div>
  <div>
      <MyComponent v-slot:default="{data}">{{data}}</MyComponent>
    </div>
  <div>
      <MyComponent #default="{data}">{{data}}</MyComponent>
    </div>
  <div>
      <MyComponent>
        <template v-slot>default</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template #default>default</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template #named>named</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template #default>default</template>
        <template #named>named</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template #one>one</template>
        <template #two>two</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template #one>one</template>
        <template #two>two</template>
        <template #[one]>one</template>
        <template #[two]>two</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template v-if="condition" #one>foo</template>
        <template v-else #one>bar</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template v-if="c1" #one>foo</template>
        <template v-else-if="c2" #one>bar</template>
        <template v-else #one>baz</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template v-for="(key, value) in xxxx" #[key]>{{value}}</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template v-for="(key, value) in xxxx" #[key]>{{value}}</template>
        <template v-for="(key, value) in yyyy" #[key]>{{value}}</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template #[key]>{{value}}</template>
        <template v-for="(key, value) in yyyy" #[key]>{{value}}</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template v-for="(value, key) in xxxx" #[key]>{{value}}</template>
        <template v-for="(key, value) in xxxx" #[key]>{{value}}</template>
      </MyComponent>
    </div>
  <div>
      <MyComponent>
        <template v-for="(key) in xxxx" #[key+value]>{{value}}</template>
        <template v-for="(key, value) in xxxx" #[key+value]>{{value}}</template>
      </MyComponent>
    </div>
  <div>
        <svg>
          <MyComponent v-slot="slotProps">
            <MyChildComponent :thing="slotProps.thing" />
          </MyComponent>
        </svg>
      </div>
  <div><MyComponent v-slot="." ><div /></MyComponent></div>
  <div>
          <div v-slot="{data}">{{data}}</div>
        </div>
  <div>
          <template v-slot:named></template>
        </div>
  <div>
          <div v-slot:named="{data}">{{data}}</div>
        </div>
  <div>
          <div><template v-slot></template></div>
        </div>
  <div>
          <MyComponent v-slot:named="{data}">{{data}}</MyComponent>
        </div>
  <div>
          <MyComponent v-slot="{data}">
            {{data}}
            <template #named></template>
          </MyComponent>
        </div>
  <div>
          <MyComponent v-slot="{data}" v-slot:one>{{data}}</MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot:one v-slot:two></template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot:one>1st</template>
            <template v-slot:one>2nd</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot:[one]>1st</template>
            <template v-slot:[one]>2nd</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot>1st</template>
            <template v-slot>2nd</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot>1st</template>
            <template v-slot:default>2nd</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-if="c1" v-slot:one>1st</template>
            <template v-slot:one>2nd</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-if="c1" v-slot:one>1st</template>
            <template v-else v-slot:one>2st</template>
            <template v-slot:one>3rd</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-for="(key, value) in definition" v-slot:one>{{value}}</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-for="(key, value) in definition" v-slot:[one]>{{value}}</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-for="(key, value) in xxxx" v-slot:key>{{value}}</template>
            <template v-for="(key, value) in yyyy" v-slot:key>{{value}}</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-for="(key, value) in xxxx" v-slot:[key]>{{value}}</template>
            <template v-for="(key, value) in xxxx" v-slot:[key]>{{value}}</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-for="(key) in xxxx" v-slot:[key]>{{value}}</template>
            <template v-for="(key, value) in xxxx" v-slot:[key]>{{value}}</template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot:[data]="{data}"></template>
          </MyComponent>
        </div>
  <div>
          <MyComponent v-slot.foo="{data}">{{data}}</MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot.foo></template>
          </MyComponent>
        </div>
  <div>
          <MyComponent>
            <template v-slot:foo.bar></template>
          </MyComponent>
        </div>
  <div>
          <MyComponent v-slot>content</MyComponent>
        </div>
  <div><MyComponent v-slot="/**/" ><div /></MyComponent></div>
  <div><MyComponent v-slot=/**/ ><div /></MyComponent></div>
  <div><MyComponent v-slot="" ><div /></MyComponent></div>
</template>
