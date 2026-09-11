const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

pub const TaiWindow = struct {
    is_open: bool = false,
    table: ui.TaiTable = .{},
    enable_player_1: bool = true,
    enable_player_2: bool = true,

    const Self = @This();

    pub const name = "Tool Assisted Input";

    pub fn draw(self: *Self, controller: *core.Controller, tai: *core.ToolAssistedInput) void {
        if (!self.is_open) {
            return;
        }
        const render_content = imgui.igBegin(name, &self.is_open, 0);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }

        if (imgui.igBeginChild_Str("table", .{}, 0, imgui.ImGuiWindowFlags_NoMove)) {
            self.table.draw(controller, tai, &self.enable_player_1, &self.enable_player_2);
        }
        imgui.igEndChild();
    }
};
