const data = JSON.parse(readFileSync('x', 'utf8'));
declare function readFileSync(path: string, encoding: string): string;
export { data };
