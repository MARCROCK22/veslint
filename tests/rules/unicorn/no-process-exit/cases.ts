declare const process: { exit(code?: number): never; on(event: string, f: () => void): void };
process.exit();
process.exit(1);
function quit() { process.exit(2); }
process.on('SIGINT', () => { process.exit(0); });
process.on('SIGTERM', () => process.exit(0));
export { quit };
