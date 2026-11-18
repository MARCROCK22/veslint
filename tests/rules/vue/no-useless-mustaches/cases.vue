<template>
  <div>
      foo
      'foo'
      {{ foo }}
      {{ 'foo'||'bar' }}
      {{ 1 }}
      {{  }}
      {{ . }}
      {{ null }}
    </div>
  <div>
        {{ 'foo' }}
      </div>
  <div>
        {{ 'comment'/*comment*/ }}
        {{ 'comment'//comment
         }}
      </div>
  <div>
        {{ '\n' }}
        {{ '\r' }}
      </div>
  <div>
        {{ '&quot;' }}
        {{ `&quot;&apos;` }}
        {{ '\\' }}
        {{ '\\r' }}
        {{ '\' }}
        {{ `foo` }}
        {{ `foo${bar}` }}
        {{ "&apos;" }}
        {{ `foo` }}
      </div>
  <div>
        {{ &apos;msg&apos; }}
        {{ &quot;msg&quot; }}
        {{ &apos;msg' }}
        {{ &quot;msg" }}
        {{ 'msg&apos; }}
        {{ "msg&quot; }}
        {{ &#39;&lt;msg&gt;&apos; }}
        {{ &#34;I&apos;m&#x22; }}
        {{ "no semi&#34 }}
      </div>
  <div>
        {{ 'I\'m' }}
        {{ "\"Happy\"" }}
        {{ `backtick \` and dollar \$` }}
        {{ "\\" }}
      </div>
  <div>
        {{ '&lt;' }}
        {{ '&gt;' }}
        {{ '&amp;' }}
        {{ '&#8212;' }}
      </div>
  <div>
        {{ '<' }}
        {{ '<<' }}
        {{ 'can be < anywhere' }}
        {{ '<tag>' }}
      </div>
  <div>
        <code>{{ '{{' }} count }}</code>
        <code>{{ 'a {{ b' }}</code>
        <code>{{ '{' }}{{ '{' }} count }}</code>
        <code>{{ '\{\{' }} count }}</code>
      </div>
  <div>
        <p>{{ '&' }}copy;</p>
        <p>&{{ 'amp;' }}</p>
        <p>&am{{ 'p;' }}</p>
        <p>{{ 'Tom &' }}amp; Jerry</p>
        <p>&{{ '' }}copy;</p>
        <p>&#0000000000000000000000000000000000000000{{ '65;' }}</p>
        <p>{{ '&\amp;' }}</p>
        <p>{{ '&#92;<' }}</p>
        <p>{{ '&copy' }}cat</p>
        <p>{{ 'Tom &amp; Jerry' }}</p>
      </div>
  <div>
        {{ `foo
bar` }}
      </div>
  <div>
        {{ 'space ' }}
        {{ ' space' }}
        {{ ' space ' }}
        {{ '  ' }}
      </div>
</template>
