declare const image: string;
declare function Component(props: { src: string; href?: string }): null;
declare const components: { Image: typeof Component };

// Reported, with a fix.
const a = <a href="./page.html" />;
const b = <img src="./image.png" srcSet="./small.png 1x, ./large.png 2x" />;
const c = <link imageSrcSet="./preload.png 1x" />;
const d = <video poster="./poster.png" />;
const e = <form action="./submit"><button formAction="./alternate" /></form>;
const f = <q cite="./source" />;
const g = <img src="  ./image.png?a=1&amp;b=2  " />;
const h = <img
  srcSet=" ./small.png 1x, ./large.png 2x " />;
const i = <img src="./&#102;ile.png" />;
const j = <img src="./dir\nfile.png" />;
const k = <img src={"./image.png"} />;
const l = <img src={`./image.png`} />;
const m = <img src={/* keep */ ("./image.png") /* also keep */} />;
const n = <img src={"./&quest;query"} />;
const o = <>🦄
<img src={"./image.png"} /><img src="./ünïcode.png" />
</>;
const p = <img srcSet="./one.png 100w,./two.png 200w, ./three.png" />;
const q = <img srcSet="./a(1).png 1x, ./b.png 2x" />;

// Not reported.
const r1 = <Component src="./image.png" href="./page.html" />;
const r2 = <components.Image src="./image.png" />;
const r3 = <img srcset="./small.png 1x" SRC="./image.png" />;
const r4 = <img srcSet={"./small.png 1x"} imageSrcSet={`./large.png 2x`} />;
const r5 = <img src={image} />;
const r6 = <img src="./&#63;query" />;
const r7 = <img src="./&quest;query" />;
const r8 = <img src="./&#63query" />;
const r9 = <img src="./&#128;.png" />;
const r10 = <img srcSet="./one.png?a=1&amp;b=2 1x" />;
const r11 = <img src={"./image.png" as string} />;
const r12 = <img src={`./${image}`} />;
const r13 = <img src={"./?query"} />;
const r14 = <img src={"./"} />;
const r15 = <img src="./C|/asset" />;
const r16 = <img srcSet="./,one.png 1x" />;
const r17 = <object data="./manual.pdf" />;
const r18 = <img src="&#32;./image.png" />;
const r19 = <img src="./image.png&#32;" />;
const r20 = <img src={String.raw`./image.png`} />;
