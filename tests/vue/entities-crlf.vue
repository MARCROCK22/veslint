<template>
  <div title="&lt;b&gt; &amp; &quot;q&quot; &lt c &amp" :x="&quot;s&quot; + c" :y="a &amp;&amp; b" :z="'&#x1F600;' + '&eacute;' + d">
    {{ a &lt; b &amp;&amp; c &gt; d }} &amp y &#32; &#x41; &#0; &#128; &nGt; &unknownentity;
    {{ '&#x1F600;' | f(x &amp; y) | g }}
    text with é ü 漢字 😀 and {{ e + '😀' + f }}
  </div>
</template>
