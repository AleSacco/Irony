const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

pub const TaiTable = struct {
    editor: ui.TaiEditor,
    state: State,
    previous_selection: ui.TaiEditor.Selection,
    previous_frame_index: ?usize,
    previous_hovered_index: ?usize,
    frame_index_before_hover: ?usize,

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
            handle_index: usize,
        };
    };
    const Items = []const core.ToolAssistedInput.SequenceItem;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .editor = .init(allocator),
            .state = .idle,
            .previous_selection = .initial,
            .previous_frame_index = null,
            .previous_hovered_index = null,
            .frame_index_before_hover = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.editor.deinit();
    }

    pub fn draw(
        self: *Self,
        tai: *core.ToolAssistedInput,
        controller: *core.Controller,
        enable_player_1: *bool,
        enable_player_2: *bool,
    ) void {
        defer self.previous_frame_index = controller.getCurrentFrameIndex();
        defer self.previous_selection = self.editor.selection;

        const table_flags = imgui.ImGuiTableFlags_ScrollY | imgui.ImGuiTableFlags_Borders;
        const is_rendered = imgui.igBeginTable("sequence", 7, table_flags, .{}, 0);
        if (!is_rendered) {
            return;
        }
        defer imgui.igEndTable();

        const items: Items = tai.sequence.items;

        imgui.igTableSetupScrollFreeze(0, 1);
        imgui.igTableSetupColumn("move", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_1_input", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("player_1_animation_frame", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("swap", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_2_animation_frame", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_2_input", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("buttons", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);

        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("move");
            defer imgui.igPopID();
            drawMenuButton();
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("player_1_input");
            defer imgui.igPopID();
            drawEnabledCheckbox(enable_player_1, .player_1);
            imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
            imgui.igTableHeader("Player 1");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("player_1_animation_frame");
            defer imgui.igPopID();
            self.drawUndoButton(tai);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("swap");
            defer imgui.igPopID();
            self.drawSwapButton(null, items);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("player_2_animation_frame");
            defer imgui.igPopID();
            self.drawRedoButton(tai);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("player_2_input");
            defer imgui.igPopID();
            drawEnabledCheckbox(enable_player_2, .player_2);
            imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
            imgui.igTableHeader("Player 2");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("buttons");
            defer imgui.igPopID();
            self.drawImportButton(tai, controller);
            imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
            self.drawClearButton(tai);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }

        const number_of_rows = std.math.lossyCast(c_int, tai.sequence.items.len +| 1);
        var clipper = imgui.ImGuiListClipper{};
        var last_clipper = clipper;
        imgui.ImGuiListClipper_Begin(&clipper, number_of_rows, imgui.igGetTextLineHeightWithSpacing());
        defer imgui.ImGuiListClipper_End(&clipper);
        while (imgui.ImGuiListClipper_Step(&clipper)) {
            last_clipper = clipper;
            var c_index = clipper.DisplayStart;
            while (c_index < clipper.DisplayEnd) : (c_index += 1) {
                imgui.igPushID_Int(c_index);
                defer imgui.igPopID();
                imgui.igTableNextRow(0, 0);

                const index = std.math.cast(usize, c_index) orelse break;
                const moved_index = self.findSimulatedMoveIndex(index, .destination_to_source, &clipper, items);
                const frame_maybe = if (index < items.len) controller.getFrameAt(index) else null;

                if (imgui.igTableNextColumn() and moved_index < items.len) {
                    self.drawMoveButton(moved_index);
                }
                if (imgui.igTableNextColumn()) {
                    const p1_index = if (self.editor.selection.isPlayerIdInside(.player_1)) moved_index else index;
                    self.drawInputCellContent(.player_1, p1_index, items, frame_maybe);
                }
                if (imgui.igTableNextColumn() and index < items.len) {
                    if (frame_maybe) |frame| {
                        drawAnimationFrameCellContent(.player_1, index, frame);
                    }
                }
                if (imgui.igTableNextColumn() and index < items.len) {
                    self.drawSwapButton(index, items);
                }
                if (imgui.igTableNextColumn() and index < items.len) {
                    if (frame_maybe) |frame| {
                        drawAnimationFrameCellContent(.player_2, index, frame);
                    }
                }
                if (imgui.igTableNextColumn()) {
                    const p2_index = if (self.editor.selection.isPlayerIdInside(.player_2)) moved_index else index;
                    self.drawInputCellContent(.player_2, p2_index, items, frame_maybe);
                }
                if (imgui.igTableNextColumn()) {
                    self.drawInsertButton(index);
                    if (index < items.len) {
                        imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
                        self.drawDeleteButton(index);
                    }
                }
            }
        }

        self.handleMouseSelect();
        self.handleMouseMove(&last_clipper, items);
        if (imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_RootAndChildWindows) and self.state == .idle) {
            self.handleKeyboardSelect(items);
            handleEnabledShortcut(enable_player_1, .player_1);
            handleEnabledShortcut(enable_player_2, .player_2);
            handleMenuShortcut();
            self.handleUndoShortcut(tai);
            self.handleRedoShortcut(tai);
            self.handleImportShortcut(tai, controller);
            self.handleClearShortcut(tai);
            self.handleMoveShortcut(items);
            self.handleSwapShortcut();
            self.handleInsertShortcut();
            self.handleDeleteShortcut();
        }

        self.editor.commit(tai) catch |err| {
            sdk.misc.error_context.append("Failed to commit tool assisted input change.", .{});
            sdk.misc.error_context.logError(err);
            self.editor.discardUncommitted();
        };

        self.syncWithController(controller, items);
        self.keepSelectionVisible(&last_clipper);
    }

    fn syncWithController(self: *Self, controller: *core.Controller, items: Items) void {
        const current_hovered_index: ?usize = if (imgui.igTableGetHoveredRow() > 0) block: {
            break :block @intCast(imgui.igTableGetHoveredRow() - 1);
        } else null;
        defer self.previous_hovered_index = current_hovered_index;

        if (controller.mode != .pause) {
            return;
        }

        const current_frame_index = controller.getCurrentFrameIndex();
        const current_selection = self.editor.selection;
        if (current_frame_index != self.previous_frame_index) {
            if (current_frame_index) |index| {
                if (index < items.len) {
                    self.editor.selection = .{
                        .start = .{ .index = index, .player_id = .player_1 },
                        .end = .{ .index = index, .player_id = .player_2 },
                    };
                }
            }
        } else if (!std.meta.eql(current_selection, self.previous_selection)) {
            const index = current_selection.end.index;
            if (index < controller.getTotalFrames() and index < items.len) {
                controller.setCurrentFrameIndex(index);
                self.frame_index_before_hover = controller.getCurrentFrameIndex();
            }
        }

        if (current_hovered_index) |index| {
            const mouse_moved = !std.meta.eql(imgui.igGetIO_Nil().*.MouseDelta, imgui.ImVec2{ .x = 0, .y = 0 });
            const scroll_moved = imgui.igGetIO_Nil().*.MouseWheel != 0;
            if ((mouse_moved or scroll_moved) and index < controller.getTotalFrames() and index < items.len) {
                controller.setCurrentFrameIndex(index);
            }
        } else {
            if (self.previous_hovered_index != null) {
                if (self.frame_index_before_hover) |index| {
                    controller.setCurrentFrameIndex(index);
                }
            }
            self.frame_index_before_hover = controller.getCurrentFrameIndex();
        }
    }

    fn keepSelectionVisible(self: *const Self, clipper: *const imgui.ImGuiListClipper) void {
        if (self.state != .idle or std.meta.eql(self.editor.selection, self.previous_selection)) {
            return;
        }

        const min_visible_index = std.math.cast(usize, clipper.DisplayStart +| 1) orelse 0;
        const max_visible_index = @max(min_visible_index, std.math.cast(usize, clipper.DisplayEnd -| 2) orelse 0);
        const number_of_visible_rows = max_visible_index + 1 - min_visible_index;

        const selection = &self.editor.selection;
        const end_index = self.editor.selection.end.index;

        if (end_index < min_visible_index) {
            const top_row_index = switch (selection.getNumberOfRows() <= number_of_visible_rows) {
                true => self.editor.selection.getMinIndex(),
                false => switch (selection.start.index > selection.end.index) {
                    true => selection.end.index,
                    false => selection.end.index - number_of_visible_rows,
                },
            };
            const float_top_row_index: f32 = @floatFromInt(top_row_index);
            imgui.igSetScrollY_Float(float_top_row_index * clipper.ItemsHeight);
        } else if (end_index > max_visible_index) {
            const top_row_index = switch (selection.getNumberOfRows() <= number_of_visible_rows) {
                true => self.editor.selection.getMaxIndex() - number_of_visible_rows,
                false => switch (selection.start.index < selection.end.index) {
                    true => selection.end.index - number_of_visible_rows,
                    false => selection.end.index,
                },
            };
            const float_top_row_index: f32 = @floatFromInt(top_row_index);
            imgui.igSetScrollY_Float(float_top_row_index * clipper.ItemsHeight);
        }
    }

    fn drawInputCellContent(
        self: *Self,
        player_id: model.PlayerId,
        index: usize,
        items: Items,
        frame_maybe: ?*const model.Frame,
    ) void {
        const CellType = enum { normal, selected, active };
        const cell_type: CellType = block: {
            if (self.editor.selection.end.player_id == player_id and self.editor.selection.end.index == index) {
                break :block .active;
            } else if (self.editor.selection.isCellInside(player_id, index)) {
                break :block .selected;
            } else {
                break :block .normal;
            }
        };
        const cell_color = switch (cell_type) {
            .normal => if (frame_maybe) |frame| block: {
                break :block switch (frame.getPlayerById(player_id).can_interact orelse true) {
                    true => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_TableRowBg],
                    false => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_TableRowBgAlt],
                };
            } else imgui.igGetStyle().*.Colors[imgui.ImGuiCol_TableRowBg],
            .selected => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_HeaderHovered],
            .active => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_HeaderActive],
        };
        imgui.igTableSetBgColor(imgui.ImGuiTableBgTarget_CellBg, imgui.igGetColorU32_Vec4(cell_color), -1);

        const added_color = imgui.ImVec4{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 };
        const removed_color = imgui.ImVec4{ .x = 1, .y = 0.5, .z = 0.5, .w = 0.3 };
        if (index >= items.len) {
            if (frame_maybe != null) {
                imgui.igTextColored(removed_color, "...");
            }
            return;
        }
        const table_input = switch (player_id) {
            .player_1 => items[index].player_1,
            .player_2 => items[index].player_2,
        };
        var table_buffer: [32]u8 = undefined;
        const table_text = block: {
            const text = std.fmt.bufPrintZ(&table_buffer, "{f}", .{table_input}) catch "error";
            break :block if (text.len > 0) text else "---";
        };
        if (frame_maybe) |frame| {
            const recording_input: model.Input = frame.getPlayerById(player_id).input orelse .{};
            if (table_input.equalsIgnoringLeftRight(recording_input)) {
                imgui.igText("%s", table_text.ptr);
            } else {
                var recording_buffer: [32]u8 = undefined;
                const recording_text = block: {
                    const text = std.fmt.bufPrintZ(&recording_buffer, "{f}", .{recording_input}) catch "error";
                    break :block if (text.len > 0) text else "---";
                };
                imgui.igTextColored(added_color, "%s", table_text.ptr);
                imgui.igSameLine(0, -1);
                imgui.igTextColored(removed_color, "%s", recording_text.ptr);
            }
        } else {
            imgui.igTextColored(added_color, "%s", table_text.ptr);
        }
    }

    fn drawAnimationFrameCellContent(player_id: model.PlayerId, index: usize, frame: *const model.Frame) void {
        const player: *const model.Player = frame.getPlayerById(player_id);

        if (player.move_phase) |move_phase| {
            const color: imgui.ImVec4 = switch (move_phase) {
                .neutral => .{ .x = 0.1, .y = 0.2, .z = 0.1, .w = 1 },
                .start_up => .{ .x = 0.2, .y = 0.1, .z = 0.1, .w = 1 },
                .active => .{ .x = 0.2, .y = 0.2, .z = 0, .w = 1 },
                .active_recovery, .recovery => .{ .x = 0.1, .y = 0.2, .z = 0.2, .w = 1 },
            };
            const color_u32 = imgui.igGetColorU32_Vec4(color);
            imgui.igTableSetBgColor(imgui.ImGuiTableBgTarget_CellBg, color_u32, -1);
        }

        if (player.animation_frame) |animation_frame| {
            var buffer: [16]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buffer, "{}", .{animation_frame}) catch "error";
            var text_size: imgui.ImVec2 = undefined;
            imgui.igCalcTextSize(&text_size, text, null, false, -1);
            var available_size: imgui.ImVec2 = undefined;
            imgui.igGetContentRegionAvail(&available_size);
            const offset = @max(0, 0.5 * (available_size.x - text_size.x));
            imgui.igSetCursorPosX(imgui.igGetCursorPosX() + offset);
            imgui.igText("%s", text.ptr);
        }

        const cell_hovered = imgui.igTableGetHoveredColumn() == imgui.igTableGetColumnIndex() and
            imgui.igTableGetHoveredRow() == index +| 1;
        if (cell_hovered and imgui.igBeginTooltip()) {
            defer imgui.igEndTooltip();
            if (player.animation_id) |animation_id| {
                var buffer: [16]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buffer, "{}", .{animation_id}) catch "error";
                imgui.igText("Animation ID:");
                imgui.igSameLine(0, -1);
                imgui.igText("%s", text.ptr);
            }
            if (player.animation_frame) |animation_frame| {
                var buffer: [16]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buffer, "{}", .{animation_frame}) catch "error";
                imgui.igText("Animation Frame:");
                imgui.igSameLine(0, -1);
                imgui.igText("%s", text.ptr);
            }
            if (player.move_phase) |move_phase| {
                const text, const color: imgui.ImVec4 = switch (move_phase) {
                    .neutral => .{ "Neutral", .{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 } },
                    .start_up => .{ "Start Up", .{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 } },
                    .active => .{ "Active", .{ .x = 1, .y = 1, .z = 0, .w = 1 } },
                    .active_recovery => .{ "Active Recovery", .{ .x = 0.5, .y = 1, .z = 1, .w = 1 } },
                    .recovery => .{ "Recovery", .{ .x = 0.5, .y = 1, .z = 1, .w = 1 } },
                };
                imgui.igText("Move Phase:");
                imgui.igSameLine(0, -1);
                imgui.igTextColored(color, "%s", text.ptr);
            }
            if (player.can_interact) |can_interact| {
                const text, const color: imgui.ImVec4 = switch (can_interact) {
                    true => .{ "Yes", .{ .x = 1, .y = 1, .z = 1, .w = 1 } },
                    false => .{ "No", .{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1 } },
                };
                imgui.igText("Can Interact:");
                imgui.igSameLine(0, -1);
                imgui.igTextColored(color, "%s", text.ptr);
            }
        }
    }

    fn handleMouseSelect(self: *Self) void {
        if (!imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
            if (self.state == .selecting) {
                self.state = .idle;
            }
            return;
        }

        const player_id: model.PlayerId = switch (imgui.igTableGetHoveredColumn()) {
            1 => .player_1,
            5 => .player_2,
            else => return,
        };
        const index = std.math.cast(usize, imgui.igTableGetHoveredRow() -| 1) orelse return;
        const cell = ui.TaiEditor.Selection.Cell{ .player_id = player_id, .index = index };

        if (imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Left, false)) {
            const mods = imgui.igGetIO_Nil().*.KeyMods;
            if (mods == 0) {
                self.state = .selecting;
                self.editor.selection = .{ .start = cell, .end = cell };
            } else if (mods == imgui.ImGuiMod_Shift) {
                self.state = .selecting;
                self.editor.selection.end = cell;
            } else if (mods == imgui.ImGuiMod_Alt and self.editor.selection.isCellInside(player_id, index)) {
                self.state = .{ .moving = .{ .handle_index = index } };
            }
        } else if (self.state == .selecting) {
            self.editor.selection.end = cell;
        }
    }

    fn handleKeyboardSelect(self: *Self, items: Items) void {
        const up_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_UpArrow, true);
        const down_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_DownArrow, true);
        const left_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_LeftArrow, true);
        const right_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_RightArrow, true);
        var detected_press = false;
        var next_cell = self.editor.selection.end;
        if (up_pressed and !down_pressed) {
            detected_press = true;
            if (next_cell.index > 0) {
                next_cell.index -= 1;
            }
        }
        if (down_pressed and !up_pressed) {
            detected_press = true;
            if (next_cell.index < items.len) {
                next_cell.index += 1;
            }
        }
        if (left_pressed and !right_pressed) {
            detected_press = true;
            next_cell.player_id = .player_1;
        }
        if (right_pressed and !left_pressed) {
            detected_press = true;
            next_cell.player_id = .player_2;
        }
        if (detected_press) {
            const mods = imgui.igGetIO_Nil().*.KeyMods;
            if (mods == 0) {
                self.editor.selection = .{ .start = next_cell, .end = next_cell };
            } else if (mods == imgui.ImGuiMod_Shift) {
                self.editor.selection.end = next_cell;
            }
        }
    }

    fn drawEnabledCheckbox(enabled: *bool, player_id: model.PlayerId) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        _ = imgui.igCheckbox("##enabled", enabled);
        if (imgui.igIsItemHovered(0)) {
            const tooltip = switch (enabled.*) {
                false => switch (player_id) {
                    .player_1 => "Enable player 1 input simulation. [Ctrl + 1]",
                    .player_2 => "Enable player 2 input simulation. [Ctrl + 2]",
                },
                true => switch (player_id) {
                    .player_1 => "Disable player 1 input simulation. [Ctrl + 1]",
                    .player_2 => "Disable player 2 input simulation. [Ctrl + 2]",
                },
            };
            imgui.igSetTooltip(tooltip);
        }
    }

    fn handleEnabledShortcut(enabled: *bool, player_id: model.PlayerId) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Ctrl;
        const key_pressed = switch (player_id) {
            .player_1 => imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_1, false),
            .player_2 => imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_2, false),
        };
        if (correct_mods and key_pressed) {
            enabled.* = !enabled.*;
        }
    }

    fn drawMenuButton() void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        if (imgui.igButton(" ≡ ###menu", .{})) {
            // TODO
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Menu [Ctrl + M]");
        }
    }

    fn handleMenuShortcut() void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Ctrl;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_M, false);
        if (correct_mods and key_pressed) {
            // TODO
        }
    }

    fn isUndoDisabled(self: *const Self) bool {
        return !self.editor.canUndo();
    }

    fn drawUndoButton(self: *Self, tai: *core.ToolAssistedInput) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(self.isUndoDisabled());
        defer imgui.igEndDisabled();

        if (imgui.igButton(" ↶ ###undo", .{})) {
            self.editor.undo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to undo.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Undo [Ctrl + Z]");
        }
    }

    fn handleUndoShortcut(self: *Self, tai: *core.ToolAssistedInput) void {
        if (self.isUndoDisabled()) {
            return;
        }
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Ctrl;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Z, true);
        if (correct_mods and key_pressed) {
            self.editor.undo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to undo.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }

    fn isRedoDisabled(self: *const Self) bool {
        return !self.editor.canRedo();
    }

    fn drawRedoButton(self: *Self, tai: *core.ToolAssistedInput) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(self.isRedoDisabled());
        defer imgui.igEndDisabled();

        if (imgui.igButton(" ↷ ###redo", .{})) {
            self.editor.redo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to redo.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Redo [Ctrl + Y]");
        }
    }

    fn handleRedoShortcut(self: *Self, tai: *core.ToolAssistedInput) void {
        if (self.isRedoDisabled()) {
            return;
        }
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Ctrl;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Y, true);
        if (correct_mods and key_pressed) {
            self.editor.redo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to redo.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }

    fn isImportDisabled(controller: *const core.Controller) bool {
        return controller.getTotalFrames() == 0;
    }

    fn drawImportButton(self: *Self, tai: *core.ToolAssistedInput, controller: *const core.Controller) void {
        const is_confirm_open = self.state == .confirming and self.state.confirming == .import;
        var next_confirm_open = is_confirm_open;

        {
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
            defer imgui.igPopStyleVar(1);

            imgui.igBeginDisabled(isImportDisabled(controller));
            defer imgui.igEndDisabled();

            if (imgui.igButton(" → ###import", .{})) {
                if (tai.sequence.items.len == 0) {
                    self.editor.importFromRecording(tai, controller) catch |err| {
                        sdk.misc.error_context.append("Failed to import tool assisted inputs from recording.", .{});
                        sdk.misc.error_context.logError(err);
                    };
                } else {
                    next_confirm_open = true;
                }
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Import Recorded Inputs [Ctrl + I]");
            }
        }

        if (next_confirm_open) {
            imgui.igOpenPopup_Str("Import inputs from the recording?", 0);
        }
        if (imgui.igBeginPopupModal(
            "Import inputs from the recording?",
            &next_confirm_open,
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
                next_confirm_open = false;
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
                next_confirm_open = false;
            }
        }
        if (is_confirm_open != next_confirm_open) {
            switch (next_confirm_open) {
                false => self.state = .idle,
                true => self.state = .{ .confirming = .import },
            }
        }
    }

    fn handleImportShortcut(self: *Self, tai: *core.ToolAssistedInput, controller: *const core.Controller) void {
        if (isImportDisabled(controller)) {
            return;
        }
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Ctrl;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_I, false);
        if (correct_mods and key_pressed) {
            if (tai.sequence.items.len == 0) {
                self.editor.importFromRecording(tai, controller) catch |err| {
                    sdk.misc.error_context.append("Failed to import tool assisted inputs from recording.", .{});
                    sdk.misc.error_context.logError(err);
                };
            } else {
                self.state = .{ .confirming = .import };
            }
        }
    }

    fn isClearDisabled(tai: *const core.ToolAssistedInput) bool {
        return tai.sequence.items.len == 0;
    }

    fn drawClearButton(self: *Self, tai: *core.ToolAssistedInput) void {
        const is_confirm_open = self.state == .confirming and self.state.confirming == .clear;
        var next_confirm_open = is_confirm_open;

        {
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
            defer imgui.igPopStyleVar(1);

            imgui.igBeginDisabled(isClearDisabled(tai));
            defer imgui.igEndDisabled();

            if (imgui.igButton(" 🗑 ###clear", .{})) {
                next_confirm_open = true;
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Clear Table [Ctrl + Del]");
            }
        }

        if (next_confirm_open) {
            imgui.igOpenPopup_Str("Clear all inputs from the table?", 0);
        }
        if (imgui.igBeginPopupModal(
            "Clear all inputs from the table?",
            &next_confirm_open,
            imgui.ImGuiWindowFlags_AlwaysAutoResize,
        )) {
            defer imgui.igEndPopup();
            imgui.igText("Are you sure you want to clear all inputs from the table?");
            imgui.igText("This will delete all table rows and can not be undone.");
            imgui.igSeparator();
            if (imgui.igButton("Clear", .{})) {
                self.editor.clear(tai);
                imgui.igCloseCurrentPopup();
                next_confirm_open = false;
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
                next_confirm_open = false;
            }
        }
        if (is_confirm_open != next_confirm_open) {
            switch (next_confirm_open) {
                false => self.state = .idle,
                true => self.state = .{ .confirming = .clear },
            }
        }
    }

    fn handleClearShortcut(self: *Self, tai: *const core.ToolAssistedInput) void {
        if (isClearDisabled(tai)) {
            return;
        }
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Ctrl;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Delete, false);
        if (correct_mods and key_pressed) {
            self.state = .{ .confirming = .clear };
        }
    }

    fn drawMoveButton(self: *Self, index: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const is_being_moved = self.state == .moving and self.state.moving.handle_index == index;
        if (is_being_moved) {
            const active_color = imgui.igGetStyleColorVec4(imgui.ImGuiCol_ButtonActive).*;
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, active_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, active_color);
        }
        defer if (is_being_moved) {
            imgui.igPopStyleColor(2);
        };

        const selection = &self.editor.selection;
        _ = imgui.igButton(" ⋯ ###move", .{});
        if (imgui.igIsItemActivated()) {
            if (!selection.isIndexInside(index)) {
                selection.* = .{
                    .start = .{ .index = index, .player_id = .player_1 },
                    .end = .{ .index = index, .player_id = .player_2 },
                };
            }
            self.state = .{ .moving = .{ .handle_index = index } };
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                row: void,
                selected_row: void,
                selected_rows: usize,
                selected_value: void,
                selected_values: usize,
            };
            const things: Things = switch (selection.isIndexInside(index)) {
                true => switch (selection.start.player_id == selection.end.player_id) {
                    true => switch (selection.getNumberOfRows()) {
                        1 => .selected_value,
                        else => |n| .{ .selected_values = n },
                    },
                    false => switch (selection.getNumberOfRows()) {
                        1 => .selected_row,
                        else => |n| .{ .selected_rows = n },
                    },
                },
                false => .row,
            };
            var buffer: [128]u8 = undefined;
            const text = switch (things) {
                .row => "Move Row",
                .selected_row => "Move Selected Row [Alt + Up/Down] [Alt + Left Click Drag]",
                .selected_rows => |n| std.fmt.bufPrintZ(
                    &buffer,
                    "Move {} Selected Rows [Alt + Up/Down] [Alt + Left Click Drag]",
                    .{n},
                ) catch "error",
                .selected_value => "Move Selected Value [Alt + Up/Down] [Alt + Left Click Drag]",
                .selected_values => |n| std.fmt.bufPrintZ(
                    &buffer,
                    "Move {} Selected Values [Alt + Up/Down] [Alt + Left Click Drag]",
                    .{n},
                ) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleMouseMove(self: *Self, clipper: *const imgui.ImGuiListClipper, items: Items) void {
        if (self.state != .moving or imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
            return;
        }
        defer self.state = .idle;
        const selection = &self.editor.selection;
        const source_min_index = selection.getMinIndex();
        const destination_min_index = self.findSimulatedMoveIndex(
            source_min_index,
            .source_to_destination,
            clipper,
            items,
        );
        if (source_min_index == destination_min_index) {
            return;
        }
        const destination_max_index = destination_min_index + selection.getNumberOfRows() - 1;
        if (self.editor.move(destination_min_index)) {
            if (selection.start.index <= selection.end.index) {
                selection.start.index = destination_min_index;
                selection.end.index = destination_max_index;
            } else {
                selection.start.index = destination_max_index;
                selection.end.index = destination_min_index;
            }
        } else |err| {
            sdk.misc.error_context.append("Failed move inputs.", .{});
            sdk.misc.error_context.logError(err);
        }
    }

    fn findSimulatedMoveIndex(
        self: *const Self,
        index: usize,
        direction: enum { source_to_destination, destination_to_source },
        clipper: *const imgui.ImGuiListClipper,
        items: Items,
    ) usize {
        if (items.len == 0) {
            return index;
        }
        const source_handle_index = switch (self.state) {
            .moving => |*moving| moving.handle_index,
            else => return index,
        };

        var mouse_pos: imgui.ImVec2 = undefined;
        imgui.igGetMousePos(&mouse_pos);
        const float_handle_index = std.math.clamp(
            (mouse_pos.y - clipper.StartPosY) / clipper.ItemsHeight,
            0,
            @as(f32, @floatFromInt(std.math.maxInt(usize))),
        );
        const destination_handle_index: usize = @intFromFloat(float_handle_index);

        if (destination_handle_index == source_handle_index) {
            return index;
        }

        const selection = &self.editor.selection;
        var source_min_index = selection.getMinIndex();
        var source_max_index = selection.getMaxIndex();
        const number_of_rows = selection.getNumberOfRows();
        var destination_min_index = source_min_index + destination_handle_index -| source_handle_index;
        var destination_max_index = destination_min_index + number_of_rows - 1;
        if (destination_max_index + 1 > items.len) {
            destination_min_index = items.len -| number_of_rows;
            destination_max_index = destination_min_index + number_of_rows - 1;
        }

        switch (direction) {
            .source_to_destination => {},
            .destination_to_source => {
                std.mem.swap(usize, &source_min_index, &destination_min_index);
                std.mem.swap(usize, &source_max_index, &destination_max_index);
            },
        }

        if (index >= source_min_index and index <= source_max_index) {
            return index + destination_min_index - source_min_index;
        }
        if (source_min_index < destination_min_index) {
            if (index > source_max_index and index <= destination_max_index) {
                return index - number_of_rows;
            }
        } else {
            if (index >= destination_min_index and index < source_min_index) {
                return index + number_of_rows;
            }
        }
        return index;
    }

    fn handleMoveShortcut(self: *Self, items: Items) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Alt;
        if (!correct_mods) {
            return;
        }
        const up_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_UpArrow, true);
        const down_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_DownArrow, true);
        const selection = &self.editor.selection;
        const min_index = selection.getMinIndex();
        const max_index = selection.getMaxIndex();
        if (up_pressed and !down_pressed and min_index > 0) {
            if (self.editor.move(min_index - 1)) {
                selection.start.index -= 1;
                selection.end.index -= 1;
            } else |err| {
                sdk.misc.error_context.append("Failed move inputs.", .{});
                sdk.misc.error_context.logError(err);
            }
        }
        if (down_pressed and !up_pressed and max_index + 1 < items.len) {
            if (self.editor.move(min_index + 1)) {
                selection.start.index += 1;
                selection.end.index += 1;
            } else |err| {
                sdk.misc.error_context.append("Failed move inputs.", .{});
                sdk.misc.error_context.logError(err);
            }
        }
    }

    fn drawSwapButton(self: *Self, index_maybe: ?usize, items: Items) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(items.len == 0);
        defer imgui.igEndDisabled();

        const selection = &self.editor.selection;
        if (imgui.igButton(" ⇄ ###swap", .{})) {
            if (index_maybe) |index| {
                if (!selection.isIndexInside(index)) {
                    selection.* = .{
                        .start = .{ .index = index, .player_id = .player_1 },
                        .end = .{ .index = index, .player_id = .player_2 },
                    };
                }
            } else {
                selection.* = .{
                    .start = .{ .index = 0, .player_id = .player_1 },
                    .end = .{ .index = items.len - 1, .player_id = .player_2 },
                };
            }
            self.editor.swapSides() catch |err| {
                sdk.misc.error_context.append("Failed to swap input sides.", .{});
                sdk.misc.error_context.logError(err);
            };
            if (selection.start.player_id == selection.end.player_id) {
                selection.start.player_id = selection.start.player_id.getOther();
                selection.end.player_id = selection.end.player_id.getOther();
            }
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                all_rows: void,
                row: void,
                selected_row: void,
                selected_rows: usize,
            };
            const things: Things = if (index_maybe) |index| block: {
                break :block switch (selection.isIndexInside(index)) {
                    true => switch (selection.getNumberOfRows()) {
                        1 => .selected_row,
                        else => |n| .{ .selected_rows = n },
                    },
                    false => .row,
                };
            } else .all_rows;
            var buffer: [128]u8 = undefined;
            const text = switch (things) {
                .all_rows => "Swap Inputs Inside All Rows",
                .row => "Swap Inputs Inside Row",
                .selected_row => "Swap Inputs Inside Selected Row [Alt + Left/Right]",
                .selected_rows => |n| std.fmt.bufPrintZ(
                    &buffer,
                    "Swap Inputs Inside {} Selected Rows [Alt + Left/Right]",
                    .{n},
                ) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleSwapShortcut(self: *Self) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Alt;
        if (!correct_mods) {
            return;
        }
        const left_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_LeftArrow, false);
        const right_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_RightArrow, false);
        const selection = &self.editor.selection;
        if (selection.start.player_id == selection.end.player_id) {
            if (left_pressed and !right_pressed and selection.start.player_id == .player_2) {
                if (self.editor.swapSides()) {
                    selection.start.player_id = .player_1;
                    selection.end.player_id = .player_1;
                } else |err| {
                    sdk.misc.error_context.append("Failed to swap input sides.", .{});
                    sdk.misc.error_context.logError(err);
                }
            }
            if (right_pressed and !left_pressed and selection.start.player_id == .player_1) {
                if (self.editor.swapSides()) {
                    selection.start.player_id = .player_2;
                    selection.end.player_id = .player_2;
                } else |err| {
                    sdk.misc.error_context.append("Failed to swap input sides.", .{});
                    sdk.misc.error_context.logError(err);
                }
            }
        } else if (left_pressed != right_pressed) {
            self.editor.swapSides() catch |err| {
                sdk.misc.error_context.append("Failed to swap input sides.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }

    fn drawInsertButton(self: *Self, index: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const selection = &self.editor.selection;
        if (imgui.igButton(" ➕ ###insert", .{})) {
            if (!selection.isIndexInside(index)) {
                self.editor.selection = .{
                    .start = .{ .index = index, .player_id = .player_1 },
                    .end = .{ .index = index, .player_id = .player_2 },
                };
            }
            self.editor.insertRows() catch |err| {
                sdk.misc.error_context.append("Failed to insert rows.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                row: void,
                selected_row: void,
                selected_rows: usize,
            };
            const things: Things = switch (selection.isIndexInside(index)) {
                true => switch (selection.getNumberOfRows()) {
                    1 => .selected_row,
                    else => |n| .{ .selected_rows = n },
                },
                false => .row,
            };
            var buffer: [64]u8 = undefined;
            const text = switch (things) {
                .row => "Insert Row",
                .selected_row => "Insert Row [Ins]",
                .selected_rows => |n| std.fmt.bufPrintZ(&buffer, "Insert {} Rows [Ins]", .{n}) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleInsertShortcut(self: *Self) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == 0;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Insert, false);
        if (correct_mods and key_pressed) {
            self.editor.insertRows() catch |err| {
                sdk.misc.error_context.append("Failed to insert rows.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }

    fn drawDeleteButton(self: *Self, index: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const selection = &self.editor.selection;
        if (imgui.igButton(" ⌫ ###delete", .{})) {
            if (!selection.isIndexInside(index)) {
                selection.* = .{
                    .start = .{ .index = index, .player_id = .player_1 },
                    .end = .{ .index = index, .player_id = .player_2 },
                };
            }
            self.editor.deleteRows() catch |err| {
                sdk.misc.error_context.append("Failed to delete rows.", .{});
                sdk.misc.error_context.logError(err);
            };
            const min_index = selection.getMinIndex();
            selection.start.index = min_index;
            selection.end.index = min_index;
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                row: void,
                selected_row: void,
                selected_rows: usize,
            };
            const things: Things = switch (selection.isIndexInside(index)) {
                true => switch (selection.getNumberOfRows()) {
                    1 => .selected_row,
                    else => |n| .{ .selected_rows = n },
                },
                false => .row,
            };
            var buffer: [64]u8 = undefined;
            const text = switch (things) {
                .row => "Delete Row",
                .selected_row => "Delete Selected Row [Del]",
                .selected_rows => |n| std.fmt.bufPrintZ(&buffer, "Delete {} Selected Rows [Del]", .{n}) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleDeleteShortcut(self: *Self) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == 0;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Delete, false);
        if (correct_mods and key_pressed) {
            self.editor.deleteRows() catch |err| {
                sdk.misc.error_context.append("Failed to delete rows.", .{});
                sdk.misc.error_context.logError(err);
            };
            const selection = &self.editor.selection;
            const min_index = selection.getMinIndex();
            selection.start.index = min_index;
            selection.end.index = min_index;
        }
    }
};
