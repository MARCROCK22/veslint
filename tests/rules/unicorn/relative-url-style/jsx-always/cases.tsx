declare function Component(props: { src: string }): null;

// Reported, with a fix.
const a = <a href="page.html" />;
const b = <img src="image.png" srcSet="small.png 1x, large.png 2x" />;
const c = <link imageSrcSet="preload.png 1x" /> ;
const d = <form action="submit"><button formAction="alternate" /></form>;
const e = <img src={"image.png"} />;
const f = <img src={`image.png`} />;
const g = <img src={"&quest;query"} />;
const h = <img srcSet="small.png 320w, large.png 640w" />;

// Not reported.
const r1 = <img src="https://example.com/image.png" srcSet="/small.png 1x" />;
const r2 = <Component src="image.png" />;
const r3 = <form action=""><button formAction="" /></form>;
const r4 = <img src={"\u003Fquery"} />;
const r5 = <img src="./image.png" />;
const r6 = <img src="C|/asset" />;
const r7 = <img srcSet=",image.png" />;
