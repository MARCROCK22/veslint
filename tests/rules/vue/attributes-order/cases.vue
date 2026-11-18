<template>
  <div>
        <div
          ref="ref"
          v-model="model"
          v-bind="object"
          @click="handleClick"/>
      </div>
  <div>
        <div
          v-bind="object"
          ref="ref"
          v-model="model"
          @click="handleClick"/>
      </div>
  <div><div></div></div>
  <div><div is="header"></div></div>
  <div><div v-for="item in items"></div></div>
  <div><div v-if="!visible"></div></div>
  <div><div v-else-if="!visible"></div></div>
  <div><div v-else="!visible"></div></div>
  <div><div v-show="!visible"></div></div>
  <div><div v-cloak></div></div>
  <div><div v-pre></div></div>
  <div><div v-once></div></div>
  <div><div id="header"></div></div>
  <div><div key="id"></div></div>
  <div><div v-html="htmlContent"></div></div>
  <div><div v-text="textContent"></div></div>
  <div><div v-model="toggle"></div></div>
  <div><div v-custom-directive></div></div>
  <div>
        <div
          v-model="toggle"
          :bindingProp="foo"
          propOne="bar"
          model="baz">
        </div>
      </div>
  <div><div click="functionCall"></div></div>
  <div><div myProp="prop"></div></div>
  <div>
          <div
            is="header"
            v-for="item in items"
            v-if="!visible"
            v-once
            id="uniqueID"
            ref="header"
            v-model="headerData"
            myProp="prop"
            @click="functionCall"
            v-text="textContent">
          </div>
        </div>
  <div>
          <div
            is="header"
            v-for="item in items"
            v-if="!visible"
            v-once
            id="uniqueID"
            ref="header"
            v-model="headerData"
            :myProp="prop"
            v-on="functionCall"
            v-text="textContent">
          </div>
        </div>
  <div>
          <div
            is="header"
            v-for="item in items"
            v-if="!visible"
            v-once
            id="uniqueID"
            ref="header"
            :prop="headerData"
            myProp="prop"
            v-on:click="functionCall"
            v-text="textContent">
          </div>
        </div>
  <div>
          <div
            v-for="item in items"
            v-if="!visible"
            propone="prop"
            :proptwo="prop"
            propthree="prop"
            @click="functionCall"
            v-text="textContent">
          </div>
        </div>
  <div><div propone="prop" proptwo="prop" propthree="prop"></div></div>
  <div>
          <div
            id="uniqueID"
            ref="header"
            :prop="headerData"
            :[a+b]="headerData"
            :[prop]="headerData"
            myProp="prop"
            v-on:click="functionCall"
            v-on:[c]="functionCall"
            v-text="textContent">
          </div>
        </div>
  <div>
        <div
          v-if="x"
          v-bind="b"
          v-model="c"
          v-bind:value="a">
        </div>
      </div>
  <div>
        <div
          v-if="x"
          v-model="c"
          v-bind="b"
          v-bind:value="a">
        </div>
      </div>
  <div>
        <div
          v-if="x"
          v-bind="b"
          v-bind:id="a"
          v-model="c">
        </div>
      </div>
  <div><div v-cloak is="header"></div></div>
  <div><div id="uniqueID" v-cloak></div></div>
  <div>
            <div
              model="baz"
              v-model="toggle"
              propOne="bar"
              :id="foo">
            </div>
          </div>
  <div>
            <div
              :bindingProp="foo"
              model="baz"
              v-on="functionCall"
              v-model="toggle"
              propOne="bar">
            </div>
          </div>
  <div><div data-id="foo" aria-test="bar" is="custom" myProp="prop"></div></div>
  <div>
            <div v-cloak
              is="header">
            </div>
          </div>
  <div>
            <div
              v-if="!visible"
              v-for="item in items"
              v-once
              is="header"
              v-on:click="functionCall"
              ref="header"
              :prop="headerData"
              v-text="textContent"
              id="uniqueID"
              myProp="prop"
              >
            </div>
          </div>
  <div>
            <my-component
              v-if="!visible"
              v-model="content"
              v-slot="textContent"
              >
            </my-component>
          </div>
  <div><div v-cloak v-is="foo"></div></div>
  <div>
        <div
          v-bind:id="a"
          v-bind="b"
          v-if="x">
        </div>
      </div>
  <div>
        <div
          v-bind:id="a"
          v-if="x"
          v-bind="b">
        </div>
      </div>
  <div>
        <div
          v-bind="b"
          v-bind:id="a"
          v-if="x">
        </div>
      </div>
  <div>
        <div
          v-custom-directive="x"
          v-bind="b"
          v-model="c"
          v-bind:value="a">
        </div>
      </div>
  <div>
        <div
          v-if="x"
          v-model="c"
          v-bind="b"
          v-bind:id="a">
        </div>
      </div>
  <div>
        <div
          v-bind="object"
          v-if="show"
          v-model="model"
          ref="ref"
          @click="handleClick"/>
      </div>
  <div>
        <div
          @click="handleClick"
          v-bind="object"/>
      </div>
  <div>
        <div
          ref="ref"
          @click="handleClick"
          v-bind="object"
          @input="handleInput"/>
      </div>
  <div>
        <div
          @click="handleClick"
          v-bind="attrs"
        ></div>
      </div>
  <div>
        <div
          ref="ref"
          @click="handleClick"
          v-bind="attrs"
        ></div>
      </div>
</template>
