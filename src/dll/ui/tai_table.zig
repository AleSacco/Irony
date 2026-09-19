const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

pub const TaiTable = struct {
    editor: ui.TaiEditor,
    state: State,
    previous_selection: ui.TaiEditor.Selection = .initial,
    previous_frame_index: ?usize = null,

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
        controller: *core.Controller,
        enable_player_1: *bool,
        enable_player_2: *bool,
    ) void {
        defer self.previous_frame_index = controller.getCurrentFrameIndex();
        defer self.previous_selection = self.editor.selection;

        const table_flags = imgui.ImGuiTableFlags_ScrollY | imgui.ImGuiTableFlags_RowBg | imgui.ImGuiTableFlags_Borders;
        const is_rendered = imgui.igBeginTable("sequence", 7, table_flags, .{}, 0);
        if (!is_rendered) {
            return;
        }
        defer imgui.igEndTable();

        const items: Items = tai.sequence.items;

        if (imgui.igIsWindowFocused(0) and self.state == .idle) {
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
        imgui.ImGuiListClipper_Begin(&clipper, number_of_rows, -1);
        defer imgui.ImGuiListClipper_End(&clipper);
        while (imgui.ImGuiListClipper_Step(&clipper)) {
            var c_index = clipper.DisplayStart;
            while (c_index < clipper.DisplayEnd) : (c_index += 1) {
                imgui.igPushID_Int(c_index);
                defer imgui.igPopID();
                imgui.igTableNextRow(0, 0);

                const index = std.math.cast(usize, c_index) orelse break;

                if (imgui.igTableNextColumn() and index < items.len) {
                    self.drawMoveButton(index);
                }
                if (imgui.igTableNextColumn()) {
                    self.drawInputCellContent(.player_1, index, items, controller);
                }
                if (imgui.igTableNextColumn() and index < items.len) {
                    drawAnimationFrameCellContent(.player_1, index, controller);
                }
                if (imgui.igTableNextColumn() and index < items.len) {
                    self.drawSwapButton(index, items);
                }
                if (imgui.igTableNextColumn() and index < items.len) {
                    drawAnimationFrameCellContent(.player_2, index, controller);
                }
                if (imgui.igTableNextColumn()) {
                    self.drawInputCellContent(.player_2, index, items, controller);
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
        self.handleMouseMove(&clipper);

        self.editor.commit(tai) catch |err| {
            sdk.misc.error_context.append("Failed to commit tool assisted input change.", .{});
            sdk.misc.error_context.logError(err);
            self.editor.discardUncommitted();
        };

        self.syncSelectionWithController(controller, items);
    }

    fn syncSelectionWithController(self: *Self, controller: *core.Controller, items: Items) void {
        if (controller.mode != .pause) {
            return;
        }
        const current_frame_index = controller.getCurrentFrameIndex();
        const current_selection = self.editor.selection;
        if (current_frame_index != self.previous_frame_index) {
            const index_maybe = current_frame_index;
            if (index_maybe) |index| {
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
            }
        }
    }

    fn drawInputCellContent(
        self: *Self,
        player_id: model.PlayerId,
        index: usize,
        items: Items,
        controller: *const core.Controller,
    ) void {
        const CellType = enum { normal, selected, active };
        const cell_type: CellType = block: {
            const s = &self.editor.selection;
            if (s.end.player_id == player_id and s.end.index == index) {
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

        const added_color = imgui.ImVec4{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 };
        const removed_color = imgui.ImVec4{ .x = 1, .y = 0.5, .z = 0.5, .w = 0.3 };
        const recording_frame_maybe = controller.getFrameAt(index);
        if (index >= items.len) {
            if (recording_frame_maybe != null) {
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
        if (recording_frame_maybe) |recording_frame| {
            const recording_input: model.Input = recording_frame.getPlayerById(player_id).input orelse .{};
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

    fn drawAnimationFrameCellContent(
        player_id: model.PlayerId,
        index: usize,
        controller: *const core.Controller,
    ) void {
        const frame = controller.getFrameAt(index) orelse return;
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
            const color: imgui.ImVec4 = switch (player.can_interact orelse true) {
                true => .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                false => .{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1 },
            };
            imgui.igTextColored(color, "%s", text.ptr);
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
            imgui.igSetTooltip("Move Row [Alt + Up/Down]");
        }
    }

    fn handleMouseMove(self: *Self, clipper: *const imgui.ImGuiListClipper) void {
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

    fn handleMoveShortcut(self: *Self, items: Items) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == imgui.ImGuiMod_Alt;
        if (!correct_mods) {
            return;
        }
        const up_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_UpArrow, true);
        const down_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_DownArrow, true);
        const selection = &self.editor.selection;
        const min_index = @min(selection.start.index, selection.end.index);
        const max_index = @max(selection.start.index, selection.end.index);
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

    fn drawSwapButton(self: *Self, index: ?usize, items: Items) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(items.len == 0);
        defer imgui.igEndDisabled();

        if (imgui.igButton(" ⇄ ###swap", .{})) {
            self.editor.selection = .{
                .start = .{ .index = if (index) |i| i else 0, .player_id = .player_1 },
                .end = .{ .index = if (index) |i| i else items.len - 1, .player_id = .player_2 },
            };
            self.editor.swapSides() catch |err| {
                sdk.misc.error_context.append("Failed to swap input sides.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            if (index == null) {
                imgui.igSetTooltip("Swap Inputs Inside All Rows");
            } else {
                imgui.igSetTooltip("Swap Inputs Inside Row [Alt + Left/Right]");
            }
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
            imgui.igSetTooltip("Insert Row [Ins]");
        }
    }

    fn handleInsertShortcut(self: *Self) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == 0;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Insert, false);
        if (correct_mods and key_pressed) {
            self.editor.insertRows() catch |err| {
                sdk.misc.error_context.append("Failed to insert row.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }

    fn drawDeleteButton(self: *Self, index: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        if (imgui.igButton(" ⌫ ###delete", .{})) {
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
            imgui.igSetTooltip("Delete Row [Del]");
        }
    }

    fn handleDeleteShortcut(self: *Self) void {
        const correct_mods = imgui.igGetIO_Nil().*.KeyMods == 0;
        const key_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Delete, false);
        if (correct_mods and key_pressed) {
            self.editor.deleteRows() catch |err| {
                sdk.misc.error_context.append("Failed to delete row.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }
};
