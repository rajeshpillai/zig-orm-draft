const std = @import("std");
test "probe" {
    const T = *u8;
    const info = @typeInfo(T);
    switch (info) {
        .Pointer => {},
        else => {},
    }
    const S = struct {};
    const infoS = @typeInfo(S);
    switch (infoS) {
        .Struct => {},
        .@"struct" => {},
        else => {},
    }
}
