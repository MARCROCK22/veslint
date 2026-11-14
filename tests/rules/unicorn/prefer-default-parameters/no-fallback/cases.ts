export function reassign(value?: number) {
	value = value || 1;
	return value;
}
export const read = (value?: number) => value ?? 1;
const {name} = {} as {name?: string};
export const used = name ?? 'name';
