const std = @import("std");
pub fn main() void {
    const k32 = std.os.windows.kernel32;
    if (@hasDecl(k32, "GetSystemTimeAsFileTime")) {
        @compileLog("Found GetSystemTimeAsFileTime");
    }

    // Check if .c or .C is a valid tag for CallingConvention
    const CC = std.builtin.CallingConvention;
    const info = @typeInfo(CC);
    @compileLog(info.@"union".fields);
}
