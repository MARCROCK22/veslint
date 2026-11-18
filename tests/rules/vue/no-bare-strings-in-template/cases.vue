<template>
  <div>
      <h1>{{ $t('foo.bar') }}</h1>
      <h1>{{ foo }}</h1>
      <h1 v-t="'foo.bar'"></h1>
    </div>
  <div>
      <h1 v-text="'Lorem ipsum' + foo" />
      <h1 v-text="foo" />
      <h1 v-text="1" />
      <h1 v-text="true" />
      <h1 v-text />
      <h1 v-text="" />
    </div>
  <div>
      <h1>#</h1>
      <div title="#" />
    </div>
  <div>
      <div>(</div>
      <div>)</div>
      <div>,</div>
      <div>.</div>
      <div>&</div>
      <div>+</div>
      <div>-</div>
      <div>=</div>
      <div>*</div>
      <div>/</div>
      <div>#</div>
      <div>%</div>
      <div>!</div>
      <div>?</div>
      <div>:</div>
      <div>[</div>
      <div>]</div>
      <div>{</div>
      <div>}</div>
      <div title="<"></div>
      <div title=">"></div>
      <div>•</div>
      <div>—</div>
      <div> </div>
      <div>|</div>
      <div>&lpar;</div>
      <div>&rpar;</div>
      <div>&comma;</div>
      <div>&period;</div>
      <div>&amp;</div>
      <div>&AMP;</div>
      <div>&plus;</div>
      <div>&minus;</div>
      <div>&equals;</div>
      <div>&ast;</div>
      <div>&midast;</div>
      <div>&sol;</div>
      <div>&num;</div>
      <div>&percnt;</div>
      <div>&excl;</div>
      <div>&quest;</div>
      <div>&colon;</div>
      <div>&lsqb;</div>
      <div>&lbrack;</div>
      <div>&rsqb;</div>
      <div>&rbrack;</div>
      <div>&lcub;</div>
      <div>&lbrace;</div>
      <div>&rcub;</div>
      <div>&rbrace;</div>
      <div>&lt;</div>
      <div>&LT;</div>
      <div>&gt;</div>
      <div>&GT;</div>
      <div>&bull;</div>
      <div>&bullet;</div>
      <div>&mdash;</div>
      <div>&ndash;</div>
      <div>&nbsp;</div>
      <div>&Tab;</div>
      <div>&NewLine;</div>
      <div>&verbar;</div>
      <div>&vert;</div>
      <div>&VerticalLine;</div>

      <div>
        ( ) , . & + - = * / # % ! ? : [ ] { }   • —   | &lpar; &rpar; &comma; &period; &amp; &AMP; &plus; &minus; &equals; &ast; &midast; &sol; &num; &percnt; &excl; &quest; &colon; &lsqb; &lbrack; &rsqb; &rbrack; &lcub; &lbrace; &rcub; &rbrace; &lt; &LT; &gt; &GT; &bull; &bullet; &mdash; &ndash; &nbsp; &Tab; &NewLine; &verbar; &vert; &VerticalLine;
      </div>

      <div
        title="( ) , . & + - = * / # % ! ? : [ ] { } < > • —   | &lpar; &rpar; &comma; &period; &amp; &AMP; &plus; &minus; &equals; &ast; &midast; &sol; &num; &percnt; &excl; &quest; &colon; &lsqb; &lbrack; &rsqb; &rbrack; &lcub; &lbrace; &rcub; &rbrace; &lt; &LT; &gt; &GT; &bull; &bullet; &mdash; &ndash; &nbsp; &Tab; &NewLine; &verbar; &vert; &VerticalLine;"
      />
    </div>
  <div>
        <h1>Lorem ipsum</h1>
        <div
          title="Lorem ipsum"
          aria-label="Lorem ipsum"
          aria-placeholder="Lorem ipsum"
          aria-roledescription="Lorem ipsum"
          aria-valuetext="Lorem ipsum"
        />
        <img alt="Lorem ipsum">
        <input placeholder="Lorem ipsum">
        <h1 v-text="'Lorem ipsum'" />
      </div>
</template>
