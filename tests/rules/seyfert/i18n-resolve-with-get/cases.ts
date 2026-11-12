import { Command, type CommandContext, ComponentCommand, type ComponentContext, Declare } from 'seyfert';

declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;
const local = { get: () => 'local', greeting: 'hi' };

@Declare({ name: 'greet', description: 'greet' })
export class Greet extends Command {
  async run(ctx: CommandContext) {
    // Reported: a locale proxy used as a string, in a template or a `+`.
    await ctx.write({ content: `${ctx.t.greeting}` });
    const a = 'Hello, ' + ctx.t.greeting;
    const b = ctx.t.farewell + '!';
    // @ts-expect-error: two objects cannot be added
    const c = ctx.t.greeting + ctx.t.nested.deep;
    const d = `${ctx.t.nested.deep} and ${ctx.t.farewell}`;
    const e = tag`${ctx.t.greeting}`;
    const f = `${`${ctx.t.greeting}`}`;
    const g = (ctx.t.greeting) + 'x';
    // @ts-expect-error: a number and an object cannot be added
    const h = 1 + 2 + ctx.t.greeting;
    const i = `${ctx.t}`;
    const j = `/* 😀 ñ */ ${ctx.t.greeting}`;
    const k = `line one
      ${ctx.t.nested.deep}`;
    const l = `${ctx.t.nested}`;

    // Not reported: resolved with .get(), another operator, or not seyfert's proxy.
    const m = `${ctx.t.greeting.get()}`;
    const n = 'x' + ctx.t.farewell.get();
    let o = '';
    o += ctx.t.greeting;
    const p = String(ctx.t.greeting);
    const q = `${local.greeting}` + local;
    // @ts-expect-error: an object cannot be subtracted from
    const r = ctx.t.greeting - 1;
    const s = `${ctx.t.nested.count(1)}`;
    return [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s];
  }
}

export class Button extends ComponentCommand {
  componentType = 'Button' as const;
  run(ctx: ComponentContext<'Button'>) {
    return ctx.write({ content: 'Pressed: ' + ctx.t.greeting });
  }
}
