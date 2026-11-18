<template>
  <div>
          <div>
            <CustomComponent v-if="some-condition" key="key1" />
            <CustomComponent v-else key="key2" />
          </div>
        </div>
  <div>
    <div>
      <CustomComponent v-if="some-condition" />
      <CustomComponent />
    </div>
        </div>
  <div>
          <div>
            <div v-if="some-condition" >
              <CustomComponent />
            </div>
            <CustomComponent v-else />
          </div>
        </div>
  <div>
          <div>
            <slot v-if="some-condition" />
            <slot v-else />
          </div>
        </div>
  <div>
          <div>
            <div v-if="someCondition" />
            <div v-else-if="otherCondition" />
            <div v-else />
          </div>
        </div>
  <div>
          <div>
            <div v-if="foo" />
            <span v-else />
          </div>
        </div>
  <div>
          <div>
            <div>
              <ComponentA v-if="foo" /> 
              <ComponentB v-else-if="bar" /> 
            </div>
            <div>
              <div>
                <ComponentA v-if="foo" />
                <ComponentB v-else-if="baz" /> 
              </div>
              <div>
                <ComponentA v-if="foo" />
                <ComponentB v-else-if="baz" />
              </div>
            </div>
            <div>
              <ComponentA v-if="foo" />
              <ComponentB v-else /> 
            </div>
            <div>
              <div v-if="foo" />
              <ComponentB v-else />
            </div>
          </div>
        </div>
  <div>
          <div>
            <div>
              <CustomComponent v-if="foo" />
              <div v-else />
            </div>
      
            <CustomComponent v-if="bar" />
          </div>
        </div>
  <div>
          <tile>
            <template v-if="state === 'foo'">
                <ComponentA>…</ComponentA>
                <ComponentB>…</ComponentB>
            </template>
            <ComponentA v-else-if="state === 'bar'" key="a">…</ComponentA>
            <ComponentA v-else-if="state === 'bar'" key="b">…</ComponentA>
          </tile>
        </div>
  <div>
          <div>
            <CustomComponent v-if="some-condition" :key="key1" />
            <CustomComponent v-else-if="other-condition" v-bind:key="key2" />
            <CustomComponent v-else key="key3" />
          </div>
        </div>
  <div>
          <div>
            <OuterComponent v-if="showOuterComponent">
              <InnerComponent v-if="showInnerComponent1" />
              <InnerComponent v-else />
            </OuterComponent>
            <OuterComponent v-else>
              <InnerComponent :key="key1" />
              <InnerComponent :key="key2" />
            </OuterComponent>
          </div>
        </div>
  <div>
          <div>
            <OuterComponent v-if="showOuterComponent">
              <InnerComponent v-if="showInnerComponent1">
                <DifferentScopeComponent />
              </InnerComponent>
              <InnerComponent v-else />
            </OuterComponent>
            <OuterComponent v-else>
              <InnerComponent />
              <InnerComponent />
            </OuterComponent>
            <DifferentScopeComponent />
          </div>
        </div>
  <div>
          <div>
            <OuterComponent v-if="showOuterComponent">
              <InnerComponent v-if="showInnerComponent1" />
              <InnerComponent v-else />
            </OuterComponent>
            <InnerComponent v-else />
          </div>
        </div>
  <div>
          <div>
            <ComponentA v-if="foo" />
            <ComponentA v-else-if="bar" />
            <ComponentB v-else />
          </div>
        </div>
  <div>
          <div>
            <ComponentA v-if="foo" />
            <ComponentB v-else-if="bar" />
            <ComponentA v-else />
          </div>
        </div>
  <div>
          <div>
            <ComponentA v-if="foo" />
            <ComponentA v-else />

            <ComponentA v-if="bar" />
            <ComponentA v-else-if="baz" />
            <ComponentA v-else />
          </div>
        </div>
  <div>
          <div>
            <ComponentA v-if="foo" :key="id" />
            <ComponentA v-else />
          </div>
        </div>
</template>
