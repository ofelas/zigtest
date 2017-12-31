const io = @import("std").io;

var stdout_file: io.File = undefined;
var stdout_file_out_stream: io.FileOutStream = undefined;
var stdout_stream: ?&io.OutStream = null;

pub fn print(comptime fmt: []const u8, args: ...) {
    const stream = getStdOutStream() %% return;
    stream.print(fmt, args) %% return;
}

fn getStdOutStream() -> %&io.OutStream {
    if (stdout_stream) |st| {
        return st;
    } else {
        stdout_file = %return io.getStdOut();
        stdout_file_out_stream = io.FileOutStream.init(&stdout_file);
        const st = &stdout_file_out_stream.stream;
        stdout_stream = st;
        return st;
    }
}
