<template>
  <div>
        <div v-if="!foo">Content</div>
      </div>
  <div>
        <div v-if="!foo">First</div>
        <div v-if="bar">Second</div>
      </div>
  <div>
        <div v-if="!foo">Content</div>
        <div v-else-if="bar">Alternative</div>
      </div>
  <div>
        <div v-if="!foo">First</div>
        <div v-else-if="!bar">Second</div>
      </div>
  <div>
        <div v-if="a != b">Not equal</div>
      </div>
  <div>
        <div v-if="a !== b">Strictly not equal</div>
      </div>
  <div>
        <div v-if="a != b">Not equal</div>
        <div v-else-if="c">Alternative</div>
      </div>
  <div>
        <div v-if="a !== b">Strictly not equal</div>
        <div v-else-if="c">Alternative</div>
      </div>
  <div>
        <div v-if="!foo">First</div>
        <div v-else-if="!bar">Second</div>
        <div v-else-if="baz">Third</div>
      </div>
  <div>
        <div v-if="!a">First</div>
        <div v-else-if="b">Second</div>
        <div v-else>Default</div>
      </div>
  <div>
        <div v-if="foo">Positive</div>
        <div v-else>Negative</div>
      </div>
  <div>
        <div v-if="foo">First</div>
        <div v-else-if="bar">Second</div>
      </div>
  <div>
        <div v-if="foo && bar">Both true</div>
        <div v-else>Otherwise</div>
      </div>
  <div>
        <div v-if="foo">
          <span v-if="!bar">Nested content</span>
        </div>
      </div>
  <div>
        <div v-if="!foo" class="primary">Content</div>
        <span v-else class="secondary">Alternative</span>
      </div>
  <div>
        <div v-if="!(foo && bar)" id="negated">Negated condition</div>
        <span v-else id="positive">Otherwise</span>
      </div>
  <div>
        <div v-if="a != b">Not equal</div>
        <div v-else>Equal</div>
      </div>
  <div>
        <div v-if="a !== b">Strictly not equal</div>
        <div v-else>Strictly equal</div>
      </div>
  <div>
        <div v-if="foo" class="first">First</div>
        <span v-else-if="!bar" class="second">Second</span>
        <p v-else class="default">Default</p>
      </div>
  <div>
        <div v-if="!a" data-first>First</div>
        <span v-else-if="!b" data-second>Second</span>
        <p v-else data-default>Default</p>
      </div>
  <div>
        <div v-if="!condition" class="div-class" div-attr="foo" div-attr-2 :div-attr-3="foo">div contents</div>
        <span v-else class="span-class" span-attr="baz" span-attr2 :span-attr-3="baz">span contents</span>
      </div>
  <div>
        <div v-if="!outer" class="outer-if">
          <span v-if="!inner" class="inner-if">Inner if content</span>
          <p v-else class="inner-else">Inner else content</p>
        </div>
        <section v-else class="outer-else">
          <span v-if="!nested" class="nested-if">Nested if content</span>
          <p v-else class="nested-else">Nested else content</p>
        </section>
      </div>
</template>
