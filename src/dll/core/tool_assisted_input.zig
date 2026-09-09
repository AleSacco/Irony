const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const game = @import("../game/root.zig");

pub const ToolAssistedInput = struct {
    allocator: std.mem.Allocator,
    sequence: Sequence,
    mode: Mode,

    const Self = @This();
    pub const Sequence = std.ArrayList(SequenceItem);
    pub const SequenceItem = struct {
        player_1: model.Input = .{},
        player_2: model.Input = .{},
    };
    pub const Mode = union(enum) {
        idle: void,
        play: PlayMode,
    };
    pub const PlayMode = struct {
        current_index: usize,
        end_index: usize,
        enable_player_1: bool,
        enable_player_2: bool,
        repeat: bool,
    };
    pub const PlayConfig = struct {
        start_index: usize = 0,
        length: usize = std.math.maxInt(usize),
        enable_player_1: bool = true,
        enable_player_2: bool = true,
        repeat: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .sequence = .empty,
            .mode = .idle,
        };
    }

    pub fn deinit(self: *Self) void {
        self.sequence.deinit(self.allocator);
    }

    pub fn processFrame(self: *Self, input_override: *game.InputOverride) void {
        switch (self.mode) {
            .idle => {
                input_override.player_1 = null;
                input_override.player_2 = null;
            },
            .play => |*mode| {
                const end_index = @min(mode.end_index, self.sequence.items.len);
                if (mode.current_index >= end_index) {
                    switch (mode.repeat) {
                        false => self.mode = .idle,
                        true => mode.current_index = 0,
                    }
                    return;
                }
                const previous_input = switch (mode.current_index) {
                    0 => SequenceItem{},
                    else => self.sequence.items[mode.current_index - 1],
                };
                const current_input = self.sequence.items[mode.current_index];
                input_override.player_1 = switch (mode.enable_player_1) {
                    true => .{
                        .previous_input = previous_input.player_1,
                        .current_input = current_input.player_1,
                    },
                    false => null,
                };
                input_override.player_2 = switch (mode.enable_player_2) {
                    true => .{
                        .previous_input = previous_input.player_2,
                        .current_input = current_input.player_2,
                    },
                    false => null,
                };
                mode.current_index += 1;
                if (mode.current_index >= end_index) {
                    switch (mode.repeat) {
                        false => self.mode = .idle,
                        true => mode.current_index = 0,
                    }
                }
            },
        }
    }

    pub fn play(self: *Self, config: *const PlayConfig) void {
        if (self.sequence.items.len == 0) {
            return;
        }
        self.mode = .{ .play = .{
            .current_index = config.start_index,
            .end_index = @min(config.start_index +| config.length, self.sequence.items.len),
            .enable_player_1 = config.enable_player_1,
            .enable_player_2 = config.enable_player_2,
            .repeat = config.repeat,
        } };
    }

    pub fn stop(self: *Self) void {
        self.mode = .idle;
    }
};

const testing = std.testing;

test "should not override inputs when idle" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should override input with input sequence when put in play mode" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.play(&.{});

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should stop overriding input when play mode is stopped" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.play(&.{});

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.stop();

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should override input with part of sequence when start index and length are used" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .up = true },
        .player_2 = .{ .down = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .left = true },
        .player_2 = .{ .right = true },
    });

    input.play(&.{ .start_index = 1, .length = 2 });

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .up = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .down = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should should override input only for enabled players when enable player values are used" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);

    input.play(&.{ .enable_player_1 = true, .enable_player_2 = false });

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expectEqual(null, input_override.player_2);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expectEqual(null, input_override.player_2);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);

    input.play(&.{ .enable_player_1 = false, .enable_player_2 = true });

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should repeat the input sequence until stopped when repeat is set to true" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.play(&.{ .repeat = true });

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.stop();

    input.processFrame(&input_override);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}
