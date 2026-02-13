# Game Design Document: Moving Day
---

## 1. Project Overview
* **Genre:** 2D Narrative Puzzle Game
* **Engine:** Godot 4.x
* **Platform:** PC / Web
* **Core Concept:** A child processes the anxiety of moving house through 7 nights of dream puzzles. Each puzzle solved "packs away" a memory.

---

## 2. Gameplay Loop
The game follows a strict Day/Night cycle repeated 7 times.

### A. The Morning (Narrative/Hub)
* **View:** Static 2D image of the bedroom.
* **State Change:** The room appears emptier each day. A new cardboard box appears by the door labeled with yesterday's item (e.g., "Toys," "Books").
* **Interaction:** Point-and-click. The player selects the **Anchor Object** to trigger the night phase.

### B. The Night (Puzzle Phase)
* **View:** Top-down 2D puzzle interface.
* **Goal:** Solve the logic puzzle to "fix" or "organize" the dream object.
* **Win State:** Completing the puzzle triggers a transition back to Morning.

---

## 3. Puzzle Mechanics (The 7 Nights)
*Note: Nights 1-4 and 6 use a shared Grid System. Night 5 uses a Node/Line System.*

### Night 1: The Flashlight (Maze)
* **Anchor:** Flashlight on the nightstand.
* **Mechanic:** Fog of War / Navigation.
* **Rules:** The map is blacked out. Only the 3x3 grid area around the player token is visible.
* **Win Condition:** Reach the "Exit" tile.

### Night 2: The Train Set (Tracks)
* **Anchor:** Wooden Train on the rug.
* **Mechanic:** Pathfinding.
* **Rules:** Place limited rail tiles (Straight, Curve, Cross) on a grid to connect Start to End. Must use all provided tiles.

### Night 3: The Game Console (Circuit Board)
* **Anchor:** Handheld Console on the desk.
* **Mechanic:** 3-Stage Circuit Puzzle.
* **Stage 1 – Rotation:** A grid of pre-placed tiles (Lines, Elbows, T-shapes). Clicking a tile rotates it 90°. Create a continuous path from the Power Source to all endpoints.
* **Stage 2 – Solder Trace:** Click-and-drag along the solved connections to lay solder, starting from the source and spreading outward across the board.
* **Stage 3 – Calibration:** 3 potentiometer knobs appear on random tiles. Drag up/down on each knob (0-100) to find the correct combination. The board gives live visual feedback: dim (too low), bright green (correct), red (too high/overdriven). Random target values each game.
* **Win Condition:** Complete all 3 stages sequentially.
* **Implementation Notes (Feb 3):**
    * **Status:** All 3 stages implemented as a single-scene sequential flow.
    * **Grid:** Fixed 5x5, non-wrapping, no barriers. Source at center (2,2).
	* **Tile Representation:** 4-bit bitmask (`R=0x01, U=0x02, L=0x04, D=0x08`). Ported from Simon Tatham's `net.c`.
	* **Generation:** Random spanning tree from center (avoids loops and crosses), then random-rotation shuffle.
	* **Stage 1 Win Check:** BFS flood-fill from source; both tiles must agree on a shared edge. All tiles with connections must be powered.
	* **Stage 2 Mechanic:** Drag-to-solder. Mouse down on a soldered tile starts the drag; moving over adjacent connected tiles solders them. Source starts pre-soldered. Win when all connected tiles are soldered.
	* **Stage 3 Mechanic:** 3 random non-source tiles get potentiometer knobs (drawn as dial indicators). Drag up/down to adjust value 0-100. Per-knob color feedback (green/yellow/red) plus overall board tint. Win tolerance: ±5 of each target value.
	* **Visuals:** Placeholder `_draw()` lines. Rotation: yellow=powered, gray=unpowered. Trace: silver=soldered, dim=unsoldered. Calibration: color shifts from dim→green→red based on accuracy. Pot knobs drawn as circles with rotation indicator lines.
	* **Files:** `scripts/net_puzzle/tile_data.gd`, `grid_manager.gd`, `tile.gd`, `net_puzzle.gd`, `net_consts.gd`; `scenes/net_puzzle/tile.tscn`, `net_puzzle.tscn`.

### Night 4: The Stars (Constellation)
* **Anchor:** Glow-in-the-dark star stickers on the ceiling.
* **Mechanic:** Loop Drawing (Loopy / Slitherlink variant).
* **Rules:** A Penrose (kite/dart) tiling of the sky. Each shape may show a number indicating how many of its edges are part of the loop. Click edges to draw lines between stars. Left-click toggles an edge ON, right-click marks it OFF.
* **Win Condition:** Form a single closed loop satisfying all number clues.
* **Implementation Notes (Feb 12):**
	* **Status:** Ported from Simon Tatham's loopy.c (Penrose P2 grid type).
	* **Grid:** Penrose P2 (kite/dart), parameters 7x5, Easy difficulty.
	* **Generation:** Robinson triangle subdivision → kite/dart faces → random loop via loopgen → clue assignment → clue removal with solver validation.
	* **Solver:** Easy only (trivial_deductions + loop_deductions). No dline or linedsf. DSF-based loop tracking.
	* **Visuals:** Single `_draw()` call. Night-sky theme: navy background, star-dot vertices, gold YES edges, dim NO marks. Clue numbers at face centroids.
	* **Input:** Nearest-edge detection (point-to-segment distance). Left=YES toggle, Right=NO toggle.
	* **Files:** `scripts/loopy_puzzle/` (consts, grid_data, penrose_gen, loop_gen, solver, grid_manager, loopy_puzzle); `scenes/loopy_puzzle/` (loopy_puzzle.tscn).

### Night 5: The Dreamcatcher (Untangle)
* **Anchor:** Tangled Kite or Wall Decoration.
* **Mechanic:** Planar Graph.
* **Rules:** Draggable nodes connected by lines. Lines turn Red if intersecting, White if clear.
* **Win Condition:** Position nodes so zero lines intersect.

### Night 6: The Stained Glass (Map Coloring)
* **Anchor:** Lamp or Coloring Book.
* **Mechanic:** Graph Theory (4-Color Theorem).
* **Rules:** Click regions to fill with one of 4 colors. Adjacent regions cannot share the same color.
* **Win Condition:** Color the entire image without conflicts.

### Night 7: The Finale (The Door)
* **Anchor:** The Locked Bedroom Door.
* **Mechanic:** A 3-stage puzzle sequence on a single screen.
	1.  **Solve Net:** Powers the lock.
	2.  **Solve Untangle:** Unlocks the bolts.
	3.  **Solve Magnets:** Opens the door.
* Look into Sokoban style moving box mechanic
---

## 4. Technical Architecture
*Code must be modular to meet the 2-month deadline.*

### A. Core Systems
* **`GameManager` (Singleton):** Tracks `CurrentDay`, manages Save/Load, handles Scene transitions.
* **`GridManager`:** A generic class that spawns a grid (X, Y) and handles click detection. Used by 5 of 6 puzzles.
* **`PuzzleController`:** Validates the "Win Condition" after every move.

### B. Data Structure
* Levels stored as JSON or Arrays (not hard-coded scenes).
* *Example (Night 3):* `level_data = [0, 1, 0, 1, 1...]` (representing tile IDs).

---

## 5. Asset Requirements (Lite)

### Visuals (2D Static Sprites)
* **Room Backgrounds:** 7 variations (Full -> Progressively Emptier -> Empty).
* **Anchor Objects:** 7 sprites.
* **Puzzle Elements:**
	* Grid Square (Base)
	* Track Pieces (Straight, Turn)
	* Net Pieces (Line, Elbow, T-shape)
	* Soldier Icons (Red/Blue)
	* Nodes (Circle) & Lines

### Audio (Minimal)
* **Music:**
	* Track A: Rain/Storm (Nights 1-3).
	* Track B: Quiet Hum/Night (Nights 4-6).
	* Track C: Morning Birds (Finale).
* **SFX:** Tile Rotate, Success Chime, Footsteps.

---

## 6. Development Roadmap

* **Feb 3 – Feb 15 (Foundation):**
	* Implement `GridManager`.
	* Playable prototypes of Night 2 (Tracks) and Night 3 (Net).
* **Feb 16 – Mar 1 (Mechanics):**
	* Implement Node system for Night 5.
	* Implement Logic system for Night 4 & 6.
	* Build the "Hub" (Morning scene).
* **Mar 2 – Mar 15 (Content):**
	* Design all puzzle levels.
	* Implement Night 7 (Finale).
* **Mar 16 – Apr 3 (Polish):**
	* Import final art.
	* Add audio.
	* Bug fixing and export.

---