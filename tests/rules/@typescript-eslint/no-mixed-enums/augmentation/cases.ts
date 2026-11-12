import { Imported } from './module';
import Default from './module';

// Merged ambiently via module augmentation: the desired type comes from the imported enum.
declare module './module' {
  enum Imported {
    B = 1,
  }
}
function shadow(): void {
  enum Default {
    A = 1,
  }
  enum Imported {
    C = 'c',
  }
}
export {};
