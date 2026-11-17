<template>
  <div>
        <div v-if="foo" />
        <div v-else-if="bar" />
        <div v-else-if="baz" />
      </div>
  <div>
        <div v-if="foo" >
          <div v-else-if="foo" />
        </div>
      </div>
  <div>
        <div v-if="foo" />
        <div v-else-if="bar" />
        <div v-if="bar" />
        <div v-else-if="foo" />
      </div>
  <div>
        <div v-if="isSomething(x)" />
        <div v-else-if="isSomethingElse(x)" />

        <div v-if="a" />
        <div v-else-if="b" />
        <div v-else-if="c && d" />
        <div v-else-if="c && e" />

        <div v-if="n === 1" />
        <div v-else-if="n === 2" />
        <div v-else-if="n === 3" />
        <div v-else-if="n === 4" />
        <div v-else-if="n === 5" />
      </div>
  <div>
        <div v-if="foo" />
        <div />
        <div v-else-if="foo" />
      </div>
  <div>
        <div v-if />
        <div v-else-if />
      </div>
  <div>
        <div v-if="foo." />
        <div v-else-if="foo." />
      </div>
  <div>
        <div v-else-if="foo." />
        <div v-else-if="foo" />
      </div>
  <div><div v-if="a" /><div v-else-if="b" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c" /></div>
  <div><div v-if="true" /><div v-else-if="false" /></div>
  <div><div v-if="1" /><div v-else-if="2" /></div>
  <div><div v-if="f" /><div v-else-if="f()" /></div>
  <div><div v-if="f(a)" /><div v-else-if="g(a)" /></div>
  <div><div v-if="f(a)" /><div v-else-if="f(b)" /></div>
  <div><div v-if="a === 1" /><div v-else-if="a === 2" /></div>
  <div><div v-if="a === 1" /><div v-else-if="b === 1" /></div>
  <div><div v-if="a" /></div>
  <div><div v-if="a"><div v-if="a" /></div></div>
  <div><div v-if="a"><div v-if="b" /></div><div v-else-if="b" /></div>
  <div><div v-if="a"><div v-if="b" /><div v-else-if="a" /></div></div>
  <div><div v-if="a" /><div v-else-if="!!a" /></div>
  <div><div v-if="a === 1" /><div v-else-if="a === (1)" /></div>
  <div><div v-if="a || b" /><div v-else-if="c || d" /></div>
  <div><div v-if="a || b" /><div v-else-if="a || c" /></div>
  <div><div v-if="a" /><div v-else-if="a || b" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="a || b || c" /></div>
  <div><div v-if="a && b" /><div v-else-if="a" /><div v-else-if="b" /></div>
  <div><div v-if="a && b" /><div v-else-if="b && c" /><div v-else-if="a && c" /></div>
  <div><div v-if="a && b" /><div v-else-if="b || c" /></div>
  <div><div v-if="a" /><div v-else-if="b && (a || c)" /></div>
  <div><div v-if="a" /><div v-else-if="b && (c || d && a)" /></div>
  <div><div v-if="a && b && c" /><div v-else-if="a && b && (c || d)" /></div>
  <div>
        <div v-if="foo" />
        <div v-else-if="foo" />
      </div>
  <div>
        <div v-if="isSomething(x)" />
        <div v-else-if="isSomething(x)" />
      </div>
  <div>
        <div v-if="a" />
        <div v-else-if="b" />
        <div v-else-if="c && d" />
        <div v-else-if="c && d" />
      </div>
  <div>
        <div v-if="n === 1" />
        <div v-else-if="n === 2" />
        <div v-else-if="n === 3" />
        <div v-else-if="n === 2" />
        <div v-else-if="n === 5" />
      </div>
  <div>
        <div v-if="a || b" />
        <div v-else-if="a" />
      </div>
  <div>
        <div v-if="a" />
        <div v-else-if="b" />
        <div v-else-if="a || b" />
      </div>
  <div>
        <div v-if="a" />
        <div v-else-if="a && b" />
      </div>
  <div>
        <div v-if="a && b" />
        <div v-else-if="a && b && c" />
      </div>
  <div>
        <div v-if="a || b" />
        <div v-else-if="b && c" />
      </div>
  <div>
        <div v-if="a" />
        <div v-else-if="b && c" />
        <div v-else-if="d && (c && e && b || a)" />
      </div>
  <div>
        <div v-if="foo" />
        <div v-else-if="foo && bar" />
        <div v-else-if="baz && foo" />
      </div>
  <div>
        <div v-if="a && b" />
        <div v-else-if="a && b && c" />
        <div v-else-if="a && c && b" />
      </div>
  <div>
        <div v-if="a || b" />
        <div v-else-if="a" />
        <div v-else-if="b" />
      </div>
  <div>
        <div v-if      ="((f && e) || d) && c || (b && a)" />
        <div v-else-if ="(a && b) || (c && (d || (e && f)))" />
        <div v-else-if ="(a && b) || (c && (d || (e && f)))" />
      </div>
  <div><div v-if="a" /><div v-else-if="a" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="a" /><div v-else-if="c" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="a" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c" /><div v-else-if="a" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="b" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c" /><div v-else-if="b" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c" /><div v-else-if="b" /><div v-else-if="d" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c" /><div v-else-if="d" /><div v-else-if="b" /><div v-else-if="e" /></div>
  <div><div v-if="a" /><div v-else-if="a" /><div v-else-if="a" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="a" /><div v-else-if="b" /><div v-else-if="a" /></div>
  <div><div v-if="a"><div v-if="b" /></div><div v-else-if="a" /></div>
  <div><div v-if="a === 1" /><div v-else-if="a === 1" /></div>
  <div><div v-if="1 < a" /><div v-else-if="1 < a" /></div>
  <div><div v-if="true" /><div v-else-if="true" /></div>
  <div><div v-if="a && b" /><div v-else-if="a && b" /></div>
  <div><div v-if="a && b || c" /><div v-else-if="a && b || c" /></div>
  <div><div v-if="f(a)" /><div v-else-if="f(a)" /></div>
  <div><div v-if="a === 1" /><div v-else-if="a===1" /></div>
  <div><div v-if="a === 1" /><div v-else-if="a === /* comment */ 1" /></div>
  <div><div v-if="a || b" /><div v-else-if="a" /></div>
  <div><div v-if="a || b" /><div v-else-if="a" /><div v-else-if="b" /></div>
  <div><div v-if="a || b" /><div v-else-if="b || a" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="a || b" /></div>
  <div><div v-if="a || b" /><div v-else-if="c || d" /><div v-else-if="a || d" /></div>
  <div><div v-if="(a === b && fn(c)) || d" /><div v-else-if="fn(c) && a === b" /></div>
  <div><div v-if="a" /><div v-else-if="a && b" /></div>
  <div><div v-if="a && b" /><div v-else-if="a && b && c" /></div>
  <div><div v-if="a || c" /><div v-else-if="a && b || c" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c && a || b" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c && (a || b)" /></div>
  <div><div v-if="a" /><div v-else-if="b && c" /><div v-else-if="d && (a || e && c && b)" /></div>
  <div><div v-if="a || b && c" /><div v-else-if="b && c && d" /></div>
  <div><div v-if="a || b" /><div v-else-if="b && c" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="(a || b) && c" /></div>
  <div><div v-if="(a && (b || c)) || d" /><div v-else-if="(c || b) && e && a" /></div>
  <div><div v-if="a && b || b && c" /><div v-else-if="a && b && c" /></div>
  <div><div v-if="a" /><div v-else-if="b && c" /><div v-else-if="d && (c && e && b || a)" /></div>
  <div><div v-if="a || (b && (c || d))" /><div v-else-if="(d || c) && b" /></div>
  <div><div v-if="a || b" /><div v-else-if="(b || a) && c" /></div>
  <div><div v-if="a || b" /><div v-else-if="c" /><div v-else-if="d" /><div v-else-if="b && (a || c)" /></div>
  <div><div v-if="a || b || c" /><div v-else-if="a || (b && d) || (c && e)" /></div>
  <div><div v-if="a || (b || c)" /><div v-else-if="a || (b && c)" /></div>
  <div><div v-if="a || b" /><div v-else-if="c" /><div v-else-if="d" /><div v-else-if="(a || c) && (b || d)" /></div>
  <div><div v-if="a" /><div v-else-if="b" /><div v-else-if="c && (a || d && b)" /></div>
  <div><div v-if="a" /><div v-else-if="a || a" /></div>
  <div><div v-if="a || a" /><div v-else-if="a || a" /></div>
  <div><div v-if="a || a" /><div v-else-if="a" /></div>
  <div><div v-if="a" /><div v-else-if="a && a" /></div>
  <div><div v-if="a && a" /><div v-else-if="a && a" /></div>
  <div><div v-if="a && a" /><div v-else-if="a" /></div>
</template>
