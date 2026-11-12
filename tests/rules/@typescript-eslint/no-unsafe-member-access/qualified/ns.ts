export namespace outer {
  export namespace inner {
    export namespace deep {
      export interface Message {
        text: string;
      }
      export const value: any = 1;
    }
    export interface Short {
      n: number;
    }
  }
}
export interface Table {
  row: number[];
  loose: any;
}
