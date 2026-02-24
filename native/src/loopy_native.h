#ifndef LOOPY_NATIVE_H
#define LOOPY_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class LoopyNative : public RefCounted {
    GDCLASS(LoopyNative, RefCounted)

protected:
    static void _bind_methods();

public:
    LoopyNative();
    ~LoopyNative();

    // Generate a complete Loopy puzzle on a Penrose P2 grid.
    // Returns a Dictionary with all grid topology + clue data,
    // with dot positions already scaled to the 320x180 viewport.
    Dictionary generate_puzzle(int w, int h, int diff);
};

} // namespace godot

#endif // LOOPY_NATIVE_H
