const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const game = @import("root.zig");

pub const InputOverride = struct {
    player_1: ?Player = null,
    player_2: ?Player = null,

    const Self = @This();
    pub const Player = struct {
        previous_input: model.Input,
        current_input: model.Input,
    };

    pub fn apply(
        self: *const Self,
        comptime game_id: build_info.Game,
        player_id: game.PlayerId,
        player_side: game.PlayerSide,
        down_input: *game.Input(game_id),
        press_input: *game.Input(game_id),
    ) void {
        const override = switch (player_id) {
            .player_1 => self.player_1 orelse return,
            .player_2 => self.player_2 orelse return,
            else => return,
        };
        const previous_input = convertInput(game_id, cleanInput(override.previous_input), player_side);
        const current_input = convertInput(game_id, cleanInput(override.current_input), player_side);
        down_input.* = current_input;
        press_input.* = @bitCast(~@as(u32, @bitCast(previous_input)) & @as(u32, @bitCast(current_input)));
    }

    fn cleanInput(input: model.Input) model.Input {
        var cleaned_input = input;
        if (cleaned_input.forward and cleaned_input.back) {
            cleaned_input.forward = false;
            cleaned_input.back = false;
        }
        if (cleaned_input.left and cleaned_input.right) {
            cleaned_input.left = false;
            cleaned_input.right = false;
        }
        if (cleaned_input.up and cleaned_input.down) {
            cleaned_input.up = false;
            cleaned_input.down = false;
        }
        return cleaned_input;
    }

    fn convertInput(comptime game_id: build_info.Game, input: model.Input, side: game.PlayerSide) game.Input(game_id) {
        var game_input = game.Input(game_id){
            .up = input.up,
            .down = input.down,
            .left = switch (side) {
                .left => input.back,
                .right => input.forward,
                _ => false,
            },
            .right = switch (side) {
                .left => input.forward,
                .right => input.back,
                _ => false,
            },
            .button_1 = input.button_1,
            .button_2 = input.button_2,
            .button_3 = input.button_3,
            .button_4 = input.button_4,
            .special_style = input.special_style,
            .rage = input.rage,
        };
        switch (game_id) {
            .t7 => {},
            .t8 => {
                game_input.heat = input.heat;
            },
        }
        return game_input;
    }
};

const testing = std.testing;

test "should apply input override correctly in T7" {
    const Input = game.Input(.t7);
    const input_override = InputOverride{
        .player_1 = .{
            .previous_input = .{ .down = true, .button_1 = true },
            .current_input = .{ .down = true, .forward = true, .button_1 = true, .button_2 = true },
        },
        .player_2 = null,
    };
    var down_input = Input{};
    var press_input = Input{};

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t7, .player_1, .left, &down_input, &press_input);
    try testing.expectEqual(Input{ .down = true, .right = true, .button_1 = true, .button_2 = true }, down_input);
    try testing.expectEqual(Input{ .right = true, .button_2 = true }, press_input);

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t7, .player_1, .right, &down_input, &press_input);
    try testing.expectEqual(Input{ .down = true, .left = true, .button_1 = true, .button_2 = true }, down_input);
    try testing.expectEqual(Input{ .left = true, .button_2 = true }, press_input);

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t7, .player_2, .left, &down_input, &press_input);
    try testing.expectEqual(Input{ .button_3 = true }, down_input);
    try testing.expectEqual(Input{ .button_4 = true }, press_input);

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t7, .player_2, .right, &down_input, &press_input);
    try testing.expectEqual(Input{ .button_3 = true }, down_input);
    try testing.expectEqual(Input{ .button_4 = true }, press_input);
}

test "should apply input override correctly in T8" {
    const Input = game.Input(.t8);
    const input_override = InputOverride{
        .player_1 = null,
        .player_2 = .{
            .previous_input = .{ .up = true, .button_2 = true },
            .current_input = .{ .up = true, .back = true, .button_1 = true, .button_2 = true },
        },
    };
    var down_input = Input{};
    var press_input = Input{};

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t8, .player_1, .left, &down_input, &press_input);
    try testing.expectEqual(Input{ .button_3 = true }, down_input);
    try testing.expectEqual(Input{ .button_4 = true }, press_input);

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t8, .player_1, .right, &down_input, &press_input);
    try testing.expectEqual(Input{ .button_3 = true }, down_input);
    try testing.expectEqual(Input{ .button_4 = true }, press_input);

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t8, .player_2, .left, &down_input, &press_input);
    try testing.expectEqual(Input{ .up = true, .left = true, .button_1 = true, .button_2 = true }, down_input);
    try testing.expectEqual(Input{ .left = true, .button_1 = true }, press_input);

    down_input = .{ .button_3 = true };
    press_input = .{ .button_4 = true };
    input_override.apply(.t8, .player_2, .right, &down_input, &press_input);
    try testing.expectEqual(Input{ .up = true, .right = true, .button_1 = true, .button_2 = true }, down_input);
    try testing.expectEqual(Input{ .right = true, .button_1 = true }, press_input);
}
