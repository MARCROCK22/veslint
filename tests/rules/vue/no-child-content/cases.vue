<template>
  <div><div>foo</div></div>
  <div><div v-foo="bar" /></div>
  <div><div v-html="foo" /></div>
  <div><div v-text="foo" /></div>
  <div><div v-html="foo"></div></div>
  <div><div v-html="foo"> </div></div>
  <div>
          <div v-html="foo">
          </div>
        </div>
  <div><div v-html="foo" /><!-- bar --></div>
  <div><div v-html="foo">bar</div></div>
  <div><div v-html="foo">{{ bar }}</div></div>
  <div><div v-html="foo"><span /></div></div>
  <div><div v-html="foo"><!-- bar --></div></div>
  <div>
          <div v-html="foo">
            <!-- this is a test -->
            <span>foo</span>
            bar
          </div>
        </div>
  <div><div v-text="foo">bar</div></div>
</template>
