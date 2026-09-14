const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");

pub const TaiEditor = struct {
    allocator: std.mem.Allocator,
    selection: Selection,
    uncommitted: std.ArrayList(Change),
    undo_stack: std.ArrayList(Change),
    redo_stack: std.ArrayList(Change),

    const Self = @This();
    pub const Selection = struct {
        start: Cell,
        end: Cell,

        pub const Cell = struct {
            player_id: model.PlayerId,
            index: usize,
        };
    };

    const initial_selection = Selection{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .selection = initial_selection,
            .uncommitted = .empty,
            .undo_stack = .empty,
            .redo_stack = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.redo_stack.deinit(self.allocator);
        self.undo_stack.deinit(self.allocator);
        self.uncommitted.deinit(self.allocator);
    }

    pub fn select(self: *Self, selection: *const Selection) void {
        self.selection = selection.*;
    }

    pub fn insertRows(self: *Self) !void {
        const min_index = @min(self.selection.start.index, self.selection.end.index);
        const max_index = @max(self.selection.start.index, self.selection.end.index);
        var number_of_changes_added: usize = 0;
        errdefer for (0..number_of_changes_added) |_| {
            self.removeLastUncommittedChange();
        };
        var index = min_index;
        while (true) {
            const change = Change{ .insert_row = .{
                .index = index,
                .new_values = .{},
            } };
            self.addUncommittedChange(&change) catch |err| {
                sdk.misc.error_context.append("Failed to add insert uncommitted change for index: {}", .{index});
                return err;
            };
            number_of_changes_added += 1;
            if (index >= max_index) {
                break;
            }
            index += 1;
        }
    }

    pub fn deleteRows(self: *Self) !void {
        const min_index = @min(self.selection.start.index, self.selection.end.index);
        const max_index = @max(self.selection.start.index, self.selection.end.index);
        var number_of_changes_added: usize = 0;
        errdefer for (0..number_of_changes_added) |_| {
            self.removeLastUncommittedChange();
        };
        var index = max_index;
        while (true) {
            const change = Change{ .delete_row = .{
                .index = index,
                .old_values = .{},
            } };
            self.addUncommittedChange(&change) catch |err| {
                sdk.misc.error_context.append("Failed to add delete uncommitted change for index: {}", .{index});
                return err;
            };
            number_of_changes_added += 1;
            if (index <= min_index) {
                break;
            }
            index -= 1;
        }
    }

    pub fn move(self: *Self, destination_min_index: usize) !void {
        const columns: Change.Move.Columns = if (self.selection.start.player_id != self.selection.end.player_id) block: {
            break :block .both;
        } else switch (self.selection.start.player_id) {
            .player_1 => .player_1,
            .player_2 => .player_2,
        };
        const min_index = @min(self.selection.start.index, self.selection.end.index);
        const max_index = @max(self.selection.start.index, self.selection.end.index);
        const change = Change{ .move = .{
            .columns = columns,
            .source_index = min_index,
            .destination_index = destination_min_index,
            .number_of_rows = max_index - min_index + 1,
        } };
        self.addUncommittedChange(&change) catch |err| {
            sdk.misc.error_context.append("Failed to add move rows uncommitted change.", .{});
            return err;
        };
    }

    pub fn swapSides(self: *Self) !void {
        const min_index = @min(self.selection.start.index, self.selection.end.index);
        const max_index = @max(self.selection.start.index, self.selection.end.index);
        const change = Change{ .swap_sides = .{
            .index = min_index,
            .number_of_rows = max_index - min_index + 1,
        } };
        return self.addUncommittedChange(&change);
    }

    pub fn setValue(self: *Self, player_id: model.PlayerId, index: usize, value: model.Input) !void {
        const change = Change{ .set_value = .{
            .player_id = player_id,
            .index = index,
            .old_value = .{},
            .new_value = value,
        } };
        self.addUncommittedChange(&change) catch |err| {
            sdk.misc.error_context.append("Failed to add move rows uncommitted change.", .{});
            return err;
        };
    }

    pub fn setValues(self: *Self, value: model.Input) !void {
        const player_ids: []const model.PlayerId = switch (self.selection.start.player_id == self.selection.end.player_id) {
            true => &[1]model.PlayerId{self.selection.start.player_id},
            false => &[2]model.PlayerId{ .player_1, .player_2 },
        };
        const min_index = @min(self.selection.start.index, self.selection.end.index);
        const max_index = @max(self.selection.start.index, self.selection.end.index);
        var number_of_changes_added: usize = 0;
        errdefer for (0..number_of_changes_added) |_| {
            self.removeLastUncommittedChange();
        };
        var index = min_index;
        while (true) {
            for (player_ids) |player_id| {
                const change = Change{ .set_value = .{
                    .player_id = player_id,
                    .index = index,
                    .old_value = .{},
                    .new_value = value,
                } };
                self.addUncommittedChange(&change) catch |err| {
                    sdk.misc.error_context.append(
                        "Failed to add set value uncommitted change for {s} at index: {}",
                        .{ @tagName(player_id), index },
                    );
                    return err;
                };
                number_of_changes_added += 1;
            }
            if (index >= max_index) {
                break;
            }
            index += 1;
        }
    }

    fn addUncommittedChange(self: *Self, change: *const Change) !void {
        const is_first_change = self.uncommitted.items.len == 0;
        if (is_first_change) {
            const checkpoint = Change{ .checkpoint = .{ .selection = self.selection } };
            self.uncommitted.append(self.allocator, checkpoint) catch |err| {
                sdk.misc.error_context.new("Failed to append first change checkpoint to uncommitted changes.", .{});
                return err;
            };
        }
        errdefer if (is_first_change) {
            _ = self.uncommitted.pop();
        };
        self.uncommitted.append(self.allocator, change.*) catch |err| {
            sdk.misc.error_context.new("Failed append the change to uncommitted changes.", .{});
            return err;
        };
    }

    fn removeLastUncommittedChange(self: *Self) void {
        _ = self.uncommitted.pop();
        if (self.uncommitted.getLastOrNull()) |change| {
            switch (change) {
                .checkpoint => _ = self.uncommitted.pop(),
                else => {},
            }
        }
    }

    pub fn commit(self: *Self, tai: *core.ToolAssistedInput) !void {
        if (self.uncommitted.items.len == 0) {
            return;
        }
        self.undo_stack.ensureUnusedCapacity(self.allocator, self.uncommitted.items.len) catch |err| {
            sdk.misc.error_context.new("Failed to allocate memory to store uncommitted changes on the undo stack.", .{});
            return err;
        };
        var number_of_changes_applied: usize = 0;
        errdefer {
            var index = number_of_changes_applied;
            while (index > 0) : (index -= 1) {
                const change = &self.uncommitted.items[index - 1];
                change.undo(tai) catch unreachable;
            }
        }
        for (self.uncommitted.items, 0..) |*change, change_index| {
            change.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply uncommitted change at index: {}", .{change_index});
                return err;
            };
            number_of_changes_applied += 1;
        }
        self.undo_stack.appendSliceAssumeCapacity(self.uncommitted.items);
        self.redo_stack.clearAndFree(self.allocator);
        self.discardUncommitted();
    }

    pub fn discardUncommitted(self: *Self) void {
        if (self.uncommitted.items.len <= 32) {
            self.uncommitted.clearRetainingCapacity();
        } else {
            self.uncommitted.clearAndFree(self.allocator);
        }
    }

    pub fn canUndo(self: *const Self) bool {
        return self.undo_stack.items.len > 0;
    }

    pub fn undo(self: *Self, tai: *core.ToolAssistedInput) !void {
        if (self.undo_stack.items.len == 0) {
            sdk.misc.error_context.new("Nothing to undo.", .{});
            return error.NothingToUndo;
        }
        const old_selection = self.selection;
        errdefer self.selection = old_selection;
        const number_of_changes_to_undo = block: {
            var count: usize = 0;
            var index = self.undo_stack.items.len;
            while (index > 0) : (index -= 1) {
                count += 1;
                switch (self.undo_stack.items[index - 1]) {
                    .checkpoint => |*checkpoint| {
                        self.selection = checkpoint.selection;
                        break;
                    },
                    else => {},
                }
            }
            break :block count;
        };
        self.redo_stack.ensureUnusedCapacity(self.allocator, number_of_changes_to_undo) catch |err| {
            sdk.misc.error_context.new("Failed to allocate memory to store undone changes on the redo stack.", .{});
            return err;
        };
        var number_of_changes_undone: usize = 0;
        errdefer for (0..number_of_changes_undone) |_| {
            var change = self.redo_stack.pop() orelse unreachable;
            change.apply(tai) catch unreachable;
            self.undo_stack.appendAssumeCapacity(change);
        };
        for (0..number_of_changes_to_undo) |change_number| {
            const change = self.undo_stack.pop() orelse unreachable;
            errdefer self.undo_stack.appendAssumeCapacity(change);
            change.undo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to undo change: {}", .{change_number});
                return err;
            };
            self.redo_stack.appendAssumeCapacity(change);
            number_of_changes_undone += 1;
        }
    }

    pub fn canRedo(self: *const Self) bool {
        return self.redo_stack.items.len > 0;
    }

    pub fn redo(self: *Self, tai: *core.ToolAssistedInput) !void {
        if (self.redo_stack.items.len == 0) {
            sdk.misc.error_context.new("Nothing to redo.", .{});
            return error.NothingToRedo;
        }
        const old_selection = self.selection;
        errdefer self.selection = old_selection;
        const number_of_changes_to_redo = block: {
            var count: usize = 0;
            var is_first_checkpoint = true;
            var index = self.redo_stack.items.len;
            while (index > 0) : (index -= 1) {
                switch (self.redo_stack.items[index - 1]) {
                    .checkpoint => |*checkpoint| {
                        if (!is_first_checkpoint) {
                            break;
                        }
                        self.selection = checkpoint.selection;
                        is_first_checkpoint = false;
                    },
                    else => {},
                }
                count += 1;
            }
            break :block count;
        };
        self.undo_stack.ensureUnusedCapacity(self.allocator, number_of_changes_to_redo) catch |err| {
            sdk.misc.error_context.new("Failed to allocate memory to store redone changes on the undo stack.", .{});
            return err;
        };
        var number_of_changes_redone: usize = 0;
        errdefer for (0..number_of_changes_redone) |_| {
            const change = self.undo_stack.pop() orelse unreachable;
            change.undo(tai) catch unreachable;
            self.redo_stack.appendAssumeCapacity(change);
        };
        for (0..number_of_changes_to_redo) |change_number| {
            var change = self.redo_stack.pop() orelse unreachable;
            errdefer self.redo_stack.appendAssumeCapacity(change);
            change.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to redo change: {}", .{change_number});
                return err;
            };
            self.undo_stack.appendAssumeCapacity(change);
            number_of_changes_redone += 1;
        }
    }

    pub fn clear(self: *Self, tai: *core.ToolAssistedInput) void {
        tai.sequence.clearAndFree(tai.allocator);
        self.uncommitted.clearAndFree(self.allocator);
        self.undo_stack.clearAndFree(self.allocator);
        self.redo_stack.clearAndFree(self.allocator);
        self.selection = initial_selection;
    }

    pub fn importFromRecording(self: *Self, tai: *core.ToolAssistedInput, controller: *const core.Controller) !void {
        self.clear(tai);
        const total_frames = controller.getTotalFrames();
        tai.sequence.ensureTotalCapacity(tai.allocator, total_frames) catch |err| {
            sdk.misc.error_context.new("Failed to allocate memory for tool assisted input sequence.", .{});
            return err;
        };
        for (0..total_frames) |index| {
            const frame = controller.getFrameAt(index) orelse unreachable;
            tai.sequence.appendAssumeCapacity(.{
                .player_1 = frame.getPlayerById(.player_1).input orelse .{},
                .player_2 = frame.getPlayerById(.player_2).input orelse .{},
            });
        }
    }
};

const Change = union(enum) {
    checkpoint: Checkpoint,
    insert_row: InsertRow,
    delete_row: DeleteRow,
    move: Move,
    swap_sides: SwapSides,
    set_value: SetValue,

    pub fn apply(self: *Change, tai: *core.ToolAssistedInput) !void {
        (switch (self.*) {
            .checkpoint => {},
            .insert_row => |*insert_row| insert_row.apply(tai),
            .delete_row => |*delete_row| delete_row.apply(tai),
            .move => |*move| move.apply(tai),
            .swap_sides => |*swap_sides| swap_sides.apply(tai),
            .set_value => |*set_value| set_value.apply(tai),
        }) catch |err| {
            sdk.misc.error_context.append("Failed to apply {s} change.", .{@tagName(self.*)});
            return err;
        };
    }

    pub fn undo(self: *const Change, tai: *core.ToolAssistedInput) !void {
        (switch (self.*) {
            .checkpoint => {},
            .insert_row => |*insert_row| insert_row.undo(tai),
            .delete_row => |*delete_row| delete_row.undo(tai),
            .move => |*move| move.undo(tai),
            .swap_sides => |*swap_sides| swap_sides.undo(tai),
            .set_value => |*set_value| set_value.undo(tai),
        }) catch |err| {
            sdk.misc.error_context.append("Failed to undo {s} change.", .{@tagName(self.*)});
            return err;
        };
    }

    pub const Checkpoint = struct {
        selection: TaiEditor.Selection,
    };
    pub const InsertRow = struct {
        index: usize,
        new_values: core.ToolAssistedInput.SequenceItem,

        pub fn apply(self: *const InsertRow, tai: *core.ToolAssistedInput) !void {
            if (self.index > tai.sequence.items.len) {
                sdk.misc.error_context.new("Index out of bounds: {}", .{self.index});
                return error.IndexOutOfBounds;
            }
            tai.sequence.insert(tai.allocator, self.index, self.new_values) catch |err| {
                sdk.misc.error_context.append(
                    "Failed to insert a item into the tool assisted input sequence at index: {}",
                    .{self.index},
                );
                return err;
            };
        }

        pub fn undo(self: *const InsertRow, tai: *core.ToolAssistedInput) !void {
            var inverse = DeleteRow{
                .index = self.index,
                .old_values = self.new_values,
            };
            inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (delete row) change.", .{});
                return err;
            };
        }
    };
    pub const DeleteRow = struct {
        index: usize,
        old_values: core.ToolAssistedInput.SequenceItem,

        pub fn apply(self: *DeleteRow, tai: *core.ToolAssistedInput) !void {
            if (self.index >= tai.sequence.items.len) {
                sdk.misc.error_context.new("Index out of bounds: {}", .{self.index});
                return error.IndexOutOfBounds;
            }
            self.old_values = tai.sequence.items[self.index];
            _ = tai.sequence.orderedRemove(self.index);
        }

        pub fn undo(self: *const DeleteRow, tai: *core.ToolAssistedInput) !void {
            const inverse = InsertRow{
                .index = self.index,
                .new_values = self.old_values,
            };
            inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (insert row) change.", .{});
                return err;
            };
        }
    };
    pub const Move = struct {
        columns: Columns,
        source_index: usize,
        destination_index: usize,
        number_of_rows: usize,

        pub const Columns = enum { player_1, player_2, both };
        const SequenceItem = core.ToolAssistedInput.SequenceItem;

        pub fn apply(self: *const Move, tai: *core.ToolAssistedInput) !void {
            const items = tai.sequence.items;
            if (self.number_of_rows == 0 or self.source_index == self.destination_index) {
                return;
            }
            const source_end = std.math.add(usize, self.source_index, self.number_of_rows) catch |err| {
                sdk.misc.error_context.append("Failed to calculate source end index.", .{});
                return err;
            };
            if (source_end > items.len) {
                sdk.misc.error_context.append("Source index range out of bounds.", .{});
                return error.IndexOutOfBounds;
            }
            const destination_end = std.math.add(usize, self.destination_index, self.number_of_rows) catch |err| {
                sdk.misc.error_context.append("Failed to calculate destination end index.", .{});
                return err;
            };
            if (destination_end > items.len) {
                sdk.misc.error_context.append("Destination index range out of bounds.", .{});
                return error.IndexOutOfBounds;
            }
            const swap = switch (self.columns) {
                .player_1 => &swapPlayer1,
                .player_2 => &swapPlayer2,
                .both => &swapBoth,
            };
            if (self.destination_index < self.source_index) {
                const a_len = self.source_index - self.destination_index;
                const b_len = self.number_of_rows;
                var a = a_len;
                var b = b_len;
                var first = self.destination_index;
                var middle = self.source_index;
                while (a != 0 and b != 0) {
                    if (a <= b) {
                        for (0..a) |i| {
                            swap(&items[first + i], &items[middle + i]);
                        }
                        first += a;
                        middle += a;
                        b -= a;
                    } else {
                        for (0..b) |i| {
                            swap(&items[first + a - b + i], &items[middle + i]);
                        }
                        middle -= b;
                        a -= b;
                    }
                }
            } else {
                const a_len = self.number_of_rows;
                const b_len = self.destination_index - self.source_index;
                var a = a_len;
                var b = b_len;
                var first = self.source_index;
                var middle = source_end;
                while (a != 0 and b != 0) {
                    if (a <= b) {
                        for (0..a) |i| {
                            swap(&items[first + i], &items[middle + i]);
                        }
                        first += a;
                        middle += a;
                        b -= a;
                    } else {
                        for (0..b) |i| {
                            swap(&items[first + a - b + i], &items[middle + i]);
                        }
                        middle -= b;
                        a -= b;
                    }
                }
            }
        }

        pub fn undo(self: *const Move, tai: *core.ToolAssistedInput) !void {
            const inverse = Move{
                .columns = self.columns,
                .source_index = self.destination_index,
                .destination_index = self.source_index,
                .number_of_rows = self.number_of_rows,
            };
            inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (move) change.", .{});
                return err;
            };
        }

        fn swapPlayer1(item_1: *SequenceItem, item_2: *SequenceItem) void {
            std.mem.swap(model.Input, &item_1.player_1, &item_2.player_1);
        }

        fn swapPlayer2(item_1: *SequenceItem, item_2: *SequenceItem) void {
            std.mem.swap(model.Input, &item_1.player_2, &item_2.player_2);
        }

        fn swapBoth(item_1: *SequenceItem, item_2: *SequenceItem) void {
            std.mem.swap(core.ToolAssistedInput.SequenceItem, item_1, item_2);
        }
    };
    pub const SwapSides = struct {
        index: usize,
        number_of_rows: usize,

        pub fn apply(self: *const SwapSides, tai: *core.ToolAssistedInput) !void {
            if (self.number_of_rows == 0) {
                return;
            }
            const start = self.index;
            const end = std.math.add(usize, start, self.number_of_rows) catch |err| {
                sdk.misc.error_context.append("Failed to calculate end index.", .{});
                return err;
            };
            if (end > tai.sequence.items.len) {
                sdk.misc.error_context.append("Index range out of bounds.", .{});
                return error.IndexOutOfBounds;
            }
            for (tai.sequence.items[start..end]) |*item| {
                std.mem.swap(model.Input, &item.player_1, &item.player_2);
            }
        }

        pub fn undo(self: *const SwapSides, tai: *core.ToolAssistedInput) !void {
            return self.apply(tai);
        }
    };
    pub const SetValue = struct {
        player_id: model.PlayerId,
        index: usize,
        old_value: model.Input,
        new_value: model.Input,

        pub fn apply(self: *SetValue, tai: *core.ToolAssistedInput) !void {
            if (self.index >= tai.sequence.items.len) {
                sdk.misc.error_context.new("Index out of bounds: {}", .{self.index});
                return error.IndexOutOfBounds;
            }
            const item = &tai.sequence.items[self.index];
            const value = switch (self.player_id) {
                .player_1 => &item.player_1,
                .player_2 => &item.player_2,
            };
            self.old_value = value.*;
            value.* = self.new_value;
        }

        pub fn undo(self: *const SetValue, tai: *core.ToolAssistedInput) !void {
            var inverse = SetValue{
                .player_id = self.player_id,
                .index = self.index,
                .old_value = self.new_value,
                .new_value = self.old_value,
            };
            inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (set value) change.", .{});
                return err;
            };
        }
    };
};

const testing = std.testing;

test "select should set selection" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();

    const selection = TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    };
    editor.select(&selection);
    try testing.expectEqual(selection, editor.selection);
}

test "commit should do nothing when no uncommitted changes are pending" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try editor.commit(&tai);
    try testing.expectEqual(false, editor.canUndo());
}

test "commit should revert changes and return error when operating out of bounds" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.select(&.{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 4, .player_id = .player_2 },
    });
    try editor.setValues(.{});
    try testing.expectError(error.IndexOutOfBounds, editor.commit(&tai));

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
}

test "undo should return error when there is nothing to undo" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try testing.expectError(error.NothingToUndo, editor.undo(&tai));
}

test "redo should return error when there is nothing to redo" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try testing.expectError(error.NothingToRedo, editor.redo(&tai));
}

test "canUndo and canRedo should return correct values" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try testing.expectEqual(false, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());

    editor.select(&.{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    });
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());

    editor.select(&.{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    });
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());

    try editor.undo(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(true, editor.canRedo());

    try editor.undo(&tai);

    try testing.expectEqual(false, editor.canUndo());
    try testing.expectEqual(true, editor.canRedo());

    editor.select(&.{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    });
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());
}

test "insertRows should insert empty rows at selected indices" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.select(&.{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    });
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    editor.select(&.{
        .start = .{ .index = 6, .player_id = .player_1 },
        .end = .{ .index = 6, .player_id = .player_1 },
    });
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
    }, tai.sequence.items);
}

test "deleteRows should delete rows at selected indices" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.select(&.{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    });
    try editor.deleteRows();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    editor.select(&.{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_1 },
    });
    try editor.deleteRows();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
    }, tai.sequence.items);
}

test "move should move selected rows to specified destination index" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.select(&.{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    });
    try editor.move(3);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    }, tai.sequence.items);

    editor.select(&.{
        .start = .{ .index = 2, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    });
    try editor.move(0);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_3 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_3 = true } },
    }, tai.sequence.items);
}

test "swapSides should should swap values between player 1 and player on selected indices" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.select(&.{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    });
    try editor.swapSides();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .down = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .forward = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    editor.select(&.{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    });
    try editor.swapSides();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .up = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .button_4 = true }, .player_2 = .{ .back = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .down = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .forward = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .down = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .forward = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .up = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .button_4 = true }, .player_2 = .{ .back = true } },
    }, tai.sequence.items);
}

test "setValue should set value at specified index and player_id to specified value" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    try editor.setValue(.player_1, 1, .{ .rage = true });
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.setValue(.player_2, 2, .{ .heat = true });
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
}

test "setValues should set every cell the selection to the specified value" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.select(&.{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    });
    try editor.setValues(.{ .rage = true });
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    editor.select(&.{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    });
    try editor.setValues(.{ .heat = true });
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .heat = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .heat = true } },
    }, tai.sequence.items);
}
