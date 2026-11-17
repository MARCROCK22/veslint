<template>
  <p>one<div>two</div><p>three
  <ul><li>a<li>b</ul>
  <dl><dt>t<dd>d<dt>t2</dl>
  <div a=1 a=2 A=3></div x="1">
  <span/></Span>
  <svg viewbox="0 0 1 1"><foreignObject><div/></foreignObject><linearGradient/><desc><b>x</b></desc></svg>
  <math><mi><b>i</b></mi><annotation-xml encoding="text/html"><p>h</p></annotation-xml></math>
  <SVG><P>x<div>y</div></P></SVG>
  <Br>not void<br>void
  <div v-pre :a="b">{{ raw }}<i @click="x">{{ y }}</i></div>{{ after }}
  <textarea>{{ in textarea }} &lt; </textareax> </textarea>
  <Textarea>{{ notrcdata }}</Textarea>
  <title>{{ t }}</title>
  <style>{{ s }}</style>
  <template v-if="a"><template #b>c</template></template>
  <!-- comment --><!-- a -- b --><!---><!-- x --!><?php x ?><!DOCTYPE html><![CDATA[x]]></ >
  {{}} {{ }} {{ a }}{{ b }} }} x {{ {{ c }}
  <div :[a b]="1" :[c]="d" :[e="f" v-.a="b" v-on:click.="c" #="d" @="e"></div>
  <MyComp :fooBar="1" @Update:modelValue.Once="2"></mycomp>
</template>
<i18n lang="json">{ "a": "</i18n" }</i18n>
<docs lang="html"><b>{{ not expr }}</b></docs>
<custom>raw {{ text }} <b></custom>
