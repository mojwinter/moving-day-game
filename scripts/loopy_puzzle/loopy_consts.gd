extends RefCounted
## Shared constants for the Night 4 Constellation (Loopy) puzzle.
## Port of enums and defines from Simon Tatham's loopy.c.

const LINE_YES := 0
const LINE_UNKNOWN := 1
const LINE_NO := 2

const SOLVER_SOLVED := 0
const SOLVER_MISTAKE := 1
const SOLVER_AMBIGUOUS := 2
const SOLVER_INCOMPLETE := 3

const DIFF_EASY := 0
const DIFF_NORMAL := 1
const DIFF_TRICKY := 2
const DIFF_HARD := 3
