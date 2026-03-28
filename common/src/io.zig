const ConcurrentTimeoutError = Io.Timeout.Error || Io.Cancelable || Io.ConcurrentError;

// Extends callee's return type to contain the appropriate errors.
fn ConcurrentTimeoutResult(comptime Result: type) type {
    return switch (@typeInfo(Result)) {
        .error_union => |u| (ConcurrentTimeoutError || u.error_set)!u.payload,
        else => |T| ConcurrentTimeoutError!T,
    };
}

// Spawns a new `concurrent` task and waits until its completion with a specified `timeout`.
// This API is similar to `std.Io.operateTimeout`, except it accepts an actual function.
pub fn concurrentTimeout(
    io: Io,
    timeout: Io.Timeout,
    function: anytype,
    args: std.meta.ArgsTuple(@TypeOf(function)),
) ConcurrentTimeoutResult(@typeInfo(@TypeOf(function)).@"fn".return_type.?) {
    const Args = @TypeOf(args);
    const Result = @typeInfo(@TypeOf(function)).@"fn".return_type.?;
    const ExtendedResult = ConcurrentTimeoutResult(Result);

    const Awaiter = struct {
        io: Io,
        event: Io.Event,
        result: Result,

        pub fn complete(awaiter: *@This(), result: Result) void {
            awaiter.result = result;
            awaiter.event.set(awaiter.io);
        }
    };

    const Wrapped = struct {
        fn start(awaiter: *Awaiter, start_args: Args) void {
            awaiter.complete(@call(.auto, function, start_args));
        }
    };

    var awaiter: Awaiter = .{ .io = io, .event = .unset, .result = undefined };
    var future = try io.concurrent(Wrapped.start, .{ &awaiter, args });

    awaiter.event.waitTimeout(io, timeout) catch |wait_err| switch (wait_err) {
        error.Canceled, error.Timeout => {
            future.cancel(io);

            return switch (@typeInfo(Result)) {
                .error_union => awaiter.result catch |child_err| switch (@as(
                    @typeInfo(ExtendedResult).error_union.error_set,
                    child_err,
                )) {
                    error.Canceled, error.Timeout => wait_err,
                    else => |e| return e,
                },
                else => awaiter.result,
            };
        },
    };

    future.await(io); // Cleanup associated resources
    return awaiter.result;
}

const Io = std.Io;
const std = @import("std");
