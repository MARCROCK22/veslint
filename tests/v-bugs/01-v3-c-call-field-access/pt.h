typedef struct { unsigned int row; unsigned int column; } Pt;
static inline Pt get_pt(int x) { Pt p = { (unsigned) x, 2 }; return p; }
