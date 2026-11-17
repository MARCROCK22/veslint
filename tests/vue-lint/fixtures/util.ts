export async function load(id: number): Promise<string> {
  return String(id);
}

export const maybe: string | undefined = undefined;

export function count(items: readonly unknown[]): number {
  return items.length;
}
