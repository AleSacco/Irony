const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");

const input_text_buffer_size = 32;

pub const TaiTable = struct {
    selection: ?Selection = null,
    state: State = .idle,

    const Self = @This();
    const Selection = struct {
        start: Cell,
        end: Cell,
        active: Cell,

        pub const Cell = struct {
            player_id: model.PlayerId,
            index: usize,
        };
    };
    const State = union(enum) {
        idle: void,
        confirming: Confirming,
        selecting: void,
        moving: Moving,

        pub const Confirming = enum {
            import,
            clear,
        };
        pub const Moving = struct {
            index: usize,
        };
    };
    const Action = union(enum) {
        none: void,
        import: void,
        clear: void,
        swap: void,
        move: Move,
        insert: Insert,
        delete: Delete,

        pub const Move = struct {
            source_index: usize,
            destination_index: usize,
        };
        pub const Insert = struct {
            index: usize,
        };
        pub const Delete = struct {
            index: usize,
        };
    };

    pub fn draw(
        self: *Self,
        controller: *core.Controller,
        tai: *core.ToolAssistedInput,
        enable_player_1: *bool,
        enable_player_2: *bool,
    ) void {
        const table_flags = imgui.ImGuiTableFlags_ScrollY | imgui.ImGuiTableFlags_RowBg | imgui.ImGuiTableFlags_Borders;
        const is_rendered = imgui.igBeginTable("sequence", 4, table_flags, .{}, 0);
        if (!is_rendered) {
            return;
        }
        defer imgui.igEndTable();

        imgui.igTableSetupScrollFreeze(0, 1);
        imgui.igTableSetupColumn("move", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_1", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("player_2", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("buttons", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);

        var action: Action = .none;

        drawMoveHeader(&action, tai);
        drawPlayerHeader(enable_player_1, .player_1);
        drawPlayerHeader(enable_player_2, .player_2);
        drawButtonsHeader(&self.state, &action, controller, tai);

        const number_of_rows = std.math.lossyCast(c_int, tai.sequence.items.len +| 1);
        var clipper = imgui.ImGuiListClipper{};
        imgui.ImGuiListClipper_Begin(&clipper, number_of_rows, -1);
        defer imgui.ImGuiListClipper_End(&clipper);
        while (imgui.ImGuiListClipper_Step(&clipper)) {
            var c_index = clipper.DisplayStart;
            while (c_index < clipper.DisplayEnd) : (c_index += 1) {
                imgui.igPushID_Int(c_index);
                defer imgui.igPopID();
                imgui.igTableNextRow(0, 0);

                const index = std.math.cast(usize, c_index) orelse break;
                if (c_index < number_of_rows - 1) {
                    drawMoveCell(&self.state, index);
                    drawPlayerCell(&action, .player_1, index, &self.selection, tai);
                    drawPlayerCell(&action, .player_2, index, &self.selection, tai);
                    drawButtonsCell(&action, index, true);
                } else {
                    _ = imgui.igTableNextColumn();
                    _ = imgui.igTableNextColumn();
                    _ = imgui.igTableNextColumn();
                    drawButtonsCell(&action, index, false);
                }
            }
        }

        handleSelectLogic(&self.state, &self.selection, tai.sequence.items.len);
        handleMoveLogic(&self.state, &action, &clipper);
        executeAction(&action, controller, tai);
    }

    fn drawMoveHeader(action: *Action, tai: *const core.ToolAssistedInput) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushID_Str("buttons_1");
        defer imgui.igPopID();

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(tai.sequence.items.len == 0);
        if (imgui.igButton(" ⇄ ###swap", .{})) {
            action.* = .swap;
        }
        imgui.igEndDisabled();
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Swap Player Inputs");
        }

        imgui.igSameLine(0, 0);
        imgui.igTableHeader("");
    }

    fn drawMoveCell(state: *State, index: usize) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const is_being_moved = state.* == .moving and state.moving.index == index;
        if (is_being_moved) {
            const active_color = imgui.igGetStyleColorVec4(imgui.ImGuiCol_ButtonActive).*;
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, active_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, active_color);
        }
        defer if (is_being_moved) {
            imgui.igPopStyleColor(2);
        };

        _ = imgui.igButton(" ⋯ ###move", .{});
        if (imgui.igIsItemActivated()) {
            state.* = .{ .moving = .{ .index = index } };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Move Row");
        }
    }

    fn drawButtonsHeader(
        state: *State,
        action: *Action,
        controller: *const core.Controller,
        tai: *const core.ToolAssistedInput,
    ) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushID_Str("buttons_2");
        defer imgui.igPopID();

        const is_import_confirm_open = state.* == .confirming and state.confirming == .import;
        var next_import_confirm_open = is_import_confirm_open;
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        imgui.igBeginDisabled(controller.getTotalFrames() == 0);
        if (imgui.igButton(" → ###import", .{})) {
            if (tai.sequence.items.len == 0) {
                action.* = .import;
            } else {
                next_import_confirm_open = true;
            }
        }
        imgui.igEndDisabled();
        imgui.igPopStyleVar(1);
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Import Recorded Inputs");
        }
        if (next_import_confirm_open) {
            imgui.igOpenPopup_Str("Import inputs from the recording?", 0);
        }
        if (imgui.igBeginPopupModal(
            "Import inputs from the recording?",
            &next_import_confirm_open,
            imgui.ImGuiWindowFlags_AlwaysAutoResize,
        )) {
            defer imgui.igEndPopup();
            imgui.igText("Are you sure you want to import inputs from the recording?");
            imgui.igText("This will override all existing input values currently in the table.");
            imgui.igSeparator();
            if (imgui.igButton("Import", .{})) {
                action.* = .import;
                imgui.igCloseCurrentPopup();
                next_import_confirm_open = false;
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
                next_import_confirm_open = false;
            }
        }
        if (is_import_confirm_open != next_import_confirm_open) {
            switch (next_import_confirm_open) {
                false => state.* = .idle,
                true => state.* = .{ .confirming = .import },
            }
        }

        imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);

        const is_clear_confirm_open = state.* == .confirming and state.confirming == .clear;
        var next_clear_confirm_open = is_clear_confirm_open;
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        imgui.igBeginDisabled(tai.sequence.items.len == 0);
        if (imgui.igButton(" 🗑 ###clear", .{})) {
            next_clear_confirm_open = true;
        }
        imgui.igEndDisabled();
        imgui.igPopStyleVar(1);
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Clear Table");
        }
        if (next_clear_confirm_open) {
            imgui.igOpenPopup_Str("Clear all inputs from the table?", 0);
        }
        if (imgui.igBeginPopupModal(
            "Clear all inputs from the table?",
            &next_clear_confirm_open,
            imgui.ImGuiWindowFlags_AlwaysAutoResize,
        )) {
            defer imgui.igEndPopup();
            imgui.igText("Are you sure you want to clear all inputs from the table?");
            imgui.igText("This will delete all table rows.");
            imgui.igSeparator();
            if (imgui.igButton("Clear", .{})) {
                action.* = .clear;
                imgui.igCloseCurrentPopup();
                next_clear_confirm_open = false;
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
                next_clear_confirm_open = false;
            }
        }
        if (is_clear_confirm_open != next_clear_confirm_open) {
            switch (next_clear_confirm_open) {
                false => state.* = .idle,
                true => state.* = .{ .confirming = .clear },
            }
        }

        imgui.igSameLine(0, 0);
        imgui.igTableHeader("");
    }

    fn drawButtonsCell(action: *Action, index: usize, show_delete: bool) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        if (imgui.igButton(" ➕ ###insert", .{})) {
            action.* = .{ .insert = .{ .index = index } };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Insert Row");
        }

        if (!show_delete) {
            return;
        }

        imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);

        if (imgui.igButton(" ❎ ###delete", .{})) {
            action.* = .{ .delete = .{ .index = index } };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Delete Row");
        }
    }

    fn drawPlayerHeader(enabled: *bool, player_id: model.PlayerId) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }
        const label = switch (player_id) {
            .player_1 => "Player 1",
            .player_2 => "Player 2",
        };
        imgui.igPushID_Str(label);
        defer imgui.igPopID();

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        _ = imgui.igCheckbox("##enable", enabled);
        if (imgui.igIsItemHovered(0)) {
            const tooltip = switch (enabled.*) {
                false => switch (player_id) {
                    .player_1 => "Enable player 1 input simulation.",
                    .player_2 => "Enable player 2 input simulation.",
                },
                true => switch (player_id) {
                    .player_1 => "Disable player 1 input simulation.",
                    .player_2 => "Disable player 2 input simulation.",
                },
            };
            imgui.igSetTooltip(tooltip);
        }

        imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);

        imgui.igTableHeader(label);
    }

    fn drawPlayerCell(
        action: *Action,
        player_id: model.PlayerId,
        index: usize,
        selection: *const ?Selection,
        tai: *const core.ToolAssistedInput,
    ) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }
        imgui.igPushID_Str(switch (player_id) {
            .player_1 => "player_1",
            .player_2 => "player_2",
        });
        defer imgui.igPopID();

        const CellType = enum { normal, selected, active };
        const cell_type: CellType = block: {
            const s = if (selection.*) |*s| s else break :block .normal;
            if (player_id == s.active.player_id and index == s.active.index) {
                break :block .active;
            }
            if (index < @min(s.start.index, s.end.index) or index > @max(s.start.index, s.end.index)) {
                break :block .normal;
            }
            if (player_id != s.start.player_id and player_id != s.end.player_id) {
                break :block .normal;
            }
            break :block .selected;
        };
        switch (cell_type) {
            .normal => {},
            .selected => {
                const color = imgui.igGetStyle().*.Colors[imgui.ImGuiCol_HeaderHovered];
                const color_u32 = imgui.igGetColorU32_Vec4(color);
                imgui.igTableSetBgColor(imgui.ImGuiTableBgTarget_CellBg, color_u32, -1);
            },
            .active => {
                const color = imgui.igGetStyle().*.Colors[imgui.ImGuiCol_HeaderActive];
                const color_u32 = imgui.igGetColorU32_Vec4(color);
                imgui.igTableSetBgColor(imgui.ImGuiTableBgTarget_CellBg, color_u32, -1);
            },
        }

        const item = &tai.sequence.items[index];
        const input = switch (player_id) {
            .player_1 => item.player_1,
            .player_2 => item.player_2,
        };
        var buffer: [input_text_buffer_size]u8 = undefined;
        const input_text = writeInputText(&buffer, input);
        imgui.igText("%s", input_text.ptr);
        _ = action;
    }

    fn handleSelectLogic(state: *State, selection: *?Selection, number_of_rows: usize) void {
        if (selection.*) |*s| {
            if (number_of_rows == 0) {
                selection.* = null;
            } else {
                s.start.index = @min(s.start.index, number_of_rows - 1);
                s.end.index = @min(s.end.index, number_of_rows - 1);
                s.active.index = @min(s.active.index, number_of_rows - 1);
            }
        }

        if (!imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
            if (state.* == .selecting) {
                state.* = .idle;
            }
            return;
        }

        const player_id: model.PlayerId = switch (imgui.igTableGetHoveredColumn()) {
            1 => .player_1,
            2 => .player_2,
            else => return,
        };
        const index = std.math.cast(usize, imgui.igTableGetHoveredRow() -| 1) orelse return;
        if (index >= number_of_rows) {
            return;
        }

        if (imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Left, false)) {
            state.* = .selecting;
            const cell = Selection.Cell{ .player_id = player_id, .index = index };
            selection.* = .{ .start = cell, .end = cell, .active = cell };
        } else if (state.* == .selecting and selection.* != null) {
            selection.*.?.end = .{ .player_id = player_id, .index = index };
        }
    }

    fn handleMoveLogic(state: *State, action: *Action, clipper: *const imgui.ImGuiListClipper) void {
        const source_index = switch (state.*) {
            .moving => |*moving| moving.index,
            else => return,
        };
        if (!imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
            state.* = .idle;
            return;
        }
        if (clipper.ItemsHeight <= 0) {
            return;
        }
        var mouse_pos: imgui.ImVec2 = undefined;
        imgui.igGetMousePos(&mouse_pos);
        const float_index = std.math.clamp(
            (mouse_pos.y - clipper.StartPosY) / clipper.ItemsHeight,
            0,
            @as(f32, @floatFromInt(std.math.maxInt(usize))),
        );
        const destination_index: usize = @intFromFloat(float_index);
        if (source_index == destination_index) {
            return;
        }
        state.* = .{ .moving = .{ .index = destination_index } };
        action.* = .{ .move = .{ .source_index = source_index, .destination_index = destination_index } };
    }

    fn executeAction(
        action: *const Action,
        controller: *const core.Controller,
        tai: *core.ToolAssistedInput,
    ) void {
        switch (action.*) {
            .none => {},
            .import => {
                const total_frames = controller.getTotalFrames();
                tai.sequence.clearAndFree(tai.allocator);
                tai.sequence.ensureTotalCapacity(tai.allocator, total_frames) catch |err| {
                    sdk.misc.error_context.append("Failed to import tool assisted input table from the recording.", .{});
                    sdk.misc.error_context.logError(err);
                };
                for (0..total_frames) |index| {
                    const frame = controller.getFrameAt(index) orelse break;
                    tai.sequence.appendAssumeCapacity(.{
                        .player_1 = frame.getPlayerById(.player_1).input orelse .{},
                        .player_2 = frame.getPlayerById(.player_2).input orelse .{},
                    });
                }
            },
            .clear => {
                tai.sequence.clearAndFree(tai.allocator);
            },
            .swap => {
                for (tai.sequence.items) |*item| {
                    const temp = item.player_1;
                    item.player_1 = item.player_2;
                    item.player_2 = temp;
                }
            },
            .move => |*move| {
                if (tai.sequence.items.len == 0) {
                    return;
                }
                const source_index = @min(move.source_index, tai.sequence.items.len - 1);
                const destination_index = @min(move.destination_index, tai.sequence.items.len - 1);
                const source_value = tai.sequence.items[source_index];
                if (destination_index > source_index) {
                    std.mem.copyBackwards(
                        core.ToolAssistedInput.SequenceItem,
                        tai.sequence.items[source_index..destination_index],
                        tai.sequence.items[(source_index + 1)..(destination_index + 1)],
                    );
                } else if (destination_index < source_index) {
                    std.mem.copyForwards(
                        core.ToolAssistedInput.SequenceItem,
                        tai.sequence.items[(destination_index + 1)..(source_index + 1)],
                        tai.sequence.items[destination_index..source_index],
                    );
                } else {
                    return;
                }
                tai.sequence.items[destination_index] = source_value;
            },
            .insert => |*insert| {
                if (insert.index >= tai.sequence.items.len +| 1) {
                    return;
                }
                tai.sequence.insert(tai.allocator, insert.index, .{}) catch |err| {
                    sdk.misc.error_context.append(
                        "Failed to insert tool assisted input row at index: {}",
                        .{insert.index},
                    );
                    sdk.misc.error_context.logError(err);
                };
            },
            .delete => |*delete| {
                if (delete.index >= tai.sequence.items.len) {
                    return;
                }
                _ = tai.sequence.orderedRemove(delete.index);
            },
        }
    }
};

fn writeInputText(buffer: *[input_text_buffer_size]u8, input: model.Input) [:0]u8 {
    var writer = std.Io.Writer.fixed(buffer);
    if (input.up and !input.down) {
        writer.writeByte('u') catch {};
    }
    if (input.down and !input.up) {
        writer.writeByte('d') catch {};
    }
    if (input.forward and !input.back) {
        writer.writeByte('f') catch {};
    }
    if (input.back and !input.forward) {
        writer.writeByte('b') catch {};
    }
    var is_first = true;
    if (input.button_1) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('1') catch {};
        is_first = false;
    }
    if (input.button_2) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('2') catch {};
        is_first = false;
    }
    if (input.button_3) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('3') catch {};
        is_first = false;
    }
    if (input.button_4) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('4') catch {};
        is_first = false;
    }
    if (input.special_style) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeAll("SS") catch {};
        is_first = false;
    }
    if (input.rage) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('R') catch {};
        is_first = false;
    }
    if (input.heat) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('H') catch {};
        is_first = false;
    }
    if (writer.end == 0) {
        writer.writeAll("---") catch {};
    }
    writer.writeByte(0) catch {};
    return buffer[0..(writer.end - 1) :0];
}
