const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

const input_text_buffer_size = 32;

pub const TaiTable = struct {
    editor: ui.TaiEditor,
    state: State,

    const Self = @This();
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
    const Items = []const core.ToolAssistedInput.SequenceItem;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .editor = .init(allocator),
            .state = .idle,
        };
    }

    pub fn deinit(self: *Self) void {
        self.editor.deinit();
    }

    pub fn draw(
        self: *Self,
        tai: *core.ToolAssistedInput,
        controller: *const core.Controller,
        enable_player_1: *bool,
        enable_player_2: *bool,
    ) void {
        const table_flags = imgui.ImGuiTableFlags_ScrollY | imgui.ImGuiTableFlags_RowBg | imgui.ImGuiTableFlags_Borders;
        const is_rendered = imgui.igBeginTable("sequence", 5, table_flags, .{}, 0);
        if (!is_rendered) {
            return;
        }
        defer imgui.igEndTable();

        const items: Items = tai.sequence.items;

        imgui.igTableSetupScrollFreeze(0, 1);
        imgui.igTableSetupColumn("move", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_1", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("swap", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_2", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("buttons", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);

        self.drawMoveHeader(tai);
        drawPlayerHeader(enable_player_1, .player_1);
        self.drawSwapHeader(items);
        drawPlayerHeader(enable_player_2, .player_2);
        self.drawButtonsHeader(tai, controller);

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
                self.drawMoveCell(index, items);
                self.drawPlayerCell(.player_1, index, items);
                self.drawSwapCell(index, items);
                self.drawPlayerCell(.player_2, index, items);
                self.drawButtonsCell(index, items);
            }
        }

        self.handleSelectLogic();
        self.handleMoveLogic(&clipper);

        self.editor.commit(tai) catch |err| {
            sdk.misc.error_context.append("Failed to commit tool assisted input change.", .{});
            sdk.misc.error_context.logError(err);
            self.editor.discardUncommitted();
        };
    }

    fn drawMoveHeader(self: *Self, tai: *core.ToolAssistedInput) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushID_Str("move");
        defer imgui.igPopID();

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(!self.editor.canUndo());
        if (imgui.igButton(" ↶ ###undo", .{})) {
            self.editor.undo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to undo.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        imgui.igEndDisabled();
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Undo");
        }

        imgui.igSameLine(0, 0);
        imgui.igTableHeader("");
    }

    fn drawSwapHeader(self: *Self, items: Items) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushID_Str("swap");
        defer imgui.igPopID();

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(items.len == 0);
        if (imgui.igButton(" ⇄ ###swap", .{})) {
            self.editor.selection = .{
                .start = .{ .index = 0, .player_id = .player_1 },
                .end = .{ .index = items.len - 1, .player_id = .player_2 },
            };
            self.editor.swapSides() catch |err| {
                sdk.misc.error_context.append("Failed to swap player inputs.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        imgui.igEndDisabled();
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Swap All Player Inputs");
        }

        imgui.igSameLine(0, 0);
        imgui.igTableHeader("");
    }

    fn drawButtonsHeader(self: *Self, tai: *core.ToolAssistedInput, controller: *const core.Controller) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushID_Str("buttons");
        defer imgui.igPopID();

        const is_import_confirm_open = self.state == .confirming and self.state.confirming == .import;
        var next_import_confirm_open = is_import_confirm_open;
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        imgui.igBeginDisabled(controller.getTotalFrames() == 0);
        if (imgui.igButton(" → ###import", .{})) {
            if (tai.sequence.items.len == 0) {
                self.editor.importFromRecording(tai, controller) catch |err| {
                    sdk.misc.error_context.append("Failed to import tool assisted inputs from recording.", .{});
                    sdk.misc.error_context.logError(err);
                };
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
            imgui.igText("This will override all existing input values and can not be undone.");
            imgui.igSeparator();
            if (imgui.igButton("Import", .{})) {
                self.editor.importFromRecording(tai, controller) catch |err| {
                    sdk.misc.error_context.append("Failed to import tool assisted inputs from recording.", .{});
                    sdk.misc.error_context.logError(err);
                };
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
                false => self.state = .idle,
                true => self.state = .{ .confirming = .import },
            }
        }

        imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);

        const is_clear_confirm_open = self.state == .confirming and self.state.confirming == .clear;
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
            imgui.igText("This will delete all table rows and can not be undone.");
            imgui.igSeparator();
            if (imgui.igButton("Clear", .{})) {
                self.editor.clear(tai);
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
                false => self.state = .idle,
                true => self.state = .{ .confirming = .clear },
            }
        }

        imgui.igSameLine(0, 0);
        imgui.igTableHeader("");
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

    fn drawMoveCell(self: *Self, index: usize, items: Items) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }
        if (index >= items.len) {
            return;
        }

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const is_being_moved = self.state == .moving and self.state.moving.index == index;
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
            // TODO
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Move Row");
        }
    }

    fn drawSwapCell(self: *Self, index: usize, items: Items) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }
        if (index >= items.len) {
            return;
        }

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        if (imgui.igButton(" ⇄ ###swap", .{})) {
            self.editor.selection = .{
                .start = .{ .index = index, .player_id = .player_1 },
                .end = .{ .index = index, .player_id = .player_2 },
            };
            self.editor.swapSides() catch |err| {
                sdk.misc.error_context.append("Failed to swap player inputs.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Swap Player Inputs");
        }
    }

    fn drawButtonsCell(self: *Self, index: usize, items: Items) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        if (imgui.igButton(" ➕ ###insert", .{})) {
            self.editor.selection = .{
                .start = .{ .index = index, .player_id = .player_1 },
                .end = .{ .index = index, .player_id = .player_2 },
            };
            self.editor.insertRows() catch |err| {
                sdk.misc.error_context.append("Failed to insert row.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Insert Row");
        }

        if (index >= items.len) {
            return;
        }

        imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);

        if (imgui.igButton(" ❎ ###delete", .{})) {
            self.editor.selection = .{
                .start = .{ .index = index, .player_id = .player_1 },
                .end = .{ .index = index, .player_id = .player_2 },
            };
            self.editor.deleteRows() catch |err| {
                sdk.misc.error_context.append("Failed to delete row.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Delete Row");
        }
    }

    fn drawPlayerCell(self: *Self, player_id: model.PlayerId, index: usize, items: Items) void {
        if (!imgui.igTableNextColumn()) {
            return;
        }
        imgui.igPushID_Str(switch (player_id) {
            .player_1 => "player_1",
            .player_2 => "player_2",
        });
        defer imgui.igPopID();

        const is_selected = block: {
            const s = &self.editor.selection;
            if (index < @min(s.start.index, s.end.index) or index > @max(s.start.index, s.end.index)) {
                break :block false;
            }
            if (player_id != s.start.player_id and player_id != s.end.player_id) {
                break :block false;
            }
            break :block true;
        };
        if (is_selected) {
            const color = imgui.igGetStyle().*.Colors[imgui.ImGuiCol_HeaderHovered];
            const color_u32 = imgui.igGetColorU32_Vec4(color);
            imgui.igTableSetBgColor(imgui.ImGuiTableBgTarget_CellBg, color_u32, -1);
        }

        if (index >= items.len) {
            return;
        }
        const input = switch (player_id) {
            .player_1 => items[index].player_1,
            .player_2 => items[index].player_2,
        };
        var buffer: [input_text_buffer_size]u8 = undefined;
        const input_text = writeInputText(&buffer, input);
        imgui.igText("%s", input_text.ptr);
    }

    fn handleSelectLogic(self: *Self) void {
        if (!imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
            if (self.state == .selecting) {
                self.state = .idle;
            }
            return;
        }

        const player_id: model.PlayerId = switch (imgui.igTableGetHoveredColumn()) {
            1 => .player_1,
            3 => .player_2,
            else => return,
        };
        const index = std.math.cast(usize, imgui.igTableGetHoveredRow() -| 1) orelse return;

        if (imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Left, false)) {
            self.state = .selecting;
            self.editor.selection = .{
                .start = .{ .player_id = player_id, .index = index },
                .end = .{ .player_id = player_id, .index = index },
            };
        } else if (self.state == .selecting) {
            self.editor.selection.end = .{ .player_id = player_id, .index = index };
        }
    }

    fn handleMoveLogic(self: *Self, clipper: *const imgui.ImGuiListClipper) void {
        const source_index = switch (self.state) {
            .moving => |*moving| moving.index,
            else => return,
        };
        if (!imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
            self.state = .idle;
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
        // TODO
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
