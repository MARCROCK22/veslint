declare function work(): void;

// Reported with requireCatchParameter.
try {
  work();
} catch {
  throw new Error('failed');
}
