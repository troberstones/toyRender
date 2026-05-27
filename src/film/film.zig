const std = @import("std");
const math = @import("math");
const Spectrum = math.Spectrum;
const Tonemap = @import("tonemap.zig").Tonemap;

pub const Pixel = struct {
    accum: Spectrum = .{ .r = 0, .g = 0, .b = 0 },
    count: u32 = 0,
};

pub const Film = struct {
    width: u32,
    height: u32,
    pixels: []Pixel,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, width: u32, height: u32) !Film {
        const pixels = try alloc.alloc(Pixel, width * height);
        @memset(pixels, .{});
        return .{ .width = width, .height = height, .pixels = pixels, .alloc = alloc };
    }

    pub fn deinit(self: *Film) void {
        self.alloc.free(self.pixels);
    }

    pub fn addSample(self: *Film, px: u32, py: u32, value: Spectrum) void {
        const idx = py * self.width + px;
        self.pixels[idx].accum = Spectrum.add(self.pixels[idx].accum, value);
        self.pixels[idx].count += 1;
    }

    pub fn getPixelAvg(self: *const Film, px: u32, py: u32) Spectrum {
        const p = self.pixels[py * self.width + px];
        if (p.count == 0) return Spectrum.zero();
        return Spectrum.scale(p.accum, 1.0 / @as(f32, @floatFromInt(p.count)));
    }

    pub fn clear(self: *Film) void {
        @memset(self.pixels, .{});
    }

    pub fn writePng(self: *const Film, path: []const u8, tonemap: Tonemap) !void {
        const rgba = try self.alloc.alloc(u8, self.width * self.height * 4);
        defer self.alloc.free(rgba);
        self.toRgba8(rgba, tonemap);

        // Pack into RGB scanlines, each prefixed with filter-type byte 0 (None).
        const row_stride = 1 + self.width * 3;
        const raw = try self.alloc.alloc(u8, self.height * row_stride);
        defer self.alloc.free(raw);
        for (0..self.height) |row| {
            const rb = row * row_stride;
            raw[rb] = 0;
            for (0..self.width) |col| {
                const s = (row * self.width + col) * 4;
                raw[rb + 1 + col * 3 + 0] = rgba[s + 0];
                raw[rb + 1 + col * 3 + 1] = rgba[s + 1];
                raw[rb + 1 + col * 3 + 2] = rgba[s + 2];
            }
        }

        const idat_data = try zlibStored(self.alloc, raw);
        defer self.alloc.free(idat_data);

        const io = std.Options.debug_io;
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        var fw_buf: [65536]u8 = undefined;
        var fw = file.writer(io, &fw_buf);

        try fw.interface.writeAll("\x89PNG\r\n\x1a\n");

        var ihdr: [13]u8 = undefined;
        std.mem.writeInt(u32, ihdr[0..4], self.width, .big);
        std.mem.writeInt(u32, ihdr[4..8], self.height, .big);
        ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
        try pngChunk(&fw.interface, "IHDR", &ihdr);
        try pngChunk(&fw.interface, "IDAT", idat_data);
        try pngChunk(&fw.interface, "IEND", &[_]u8{});
        try fw.interface.flush();
    }

    // Write a scanline OpenEXR (half-float, 3 channels).
    pub fn writeExr(self: *const Film, path: []const u8) !void {
        _ = self;
        _ = path;
        // TODO: implement minimal scanline EXR writer (see src/output/exr.zig).
        @panic("Film.writeExr not yet implemented");
    }

    // Copy tone-mapped pixels into an RGBA u8 buffer for display.
    pub fn toRgba8(self: *const Film, buf: []u8, tonemap: Tonemap) void {
        std.debug.assert(buf.len >= self.width * self.height * 4);
        for (0..self.height) |row| {
            for (0..self.width) |col| {
                const s = tonemap.apply(self.getPixelAvg(@intCast(col), @intCast(row)));
                const i = (row * self.width + col) * 4;
                buf[i + 0] = linearToSrgbU8(s.r);
                buf[i + 1] = linearToSrgbU8(s.g);
                buf[i + 2] = linearToSrgbU8(s.b);
                buf[i + 3] = 255;
            }
        }
    }

    fn linearToSrgbU8(v: f32) u8 {
        const clamped = std.math.clamp(v, 0.0, 1.0);
        const encoded = if (clamped <= 0.0031308)
            clamped * 12.92
        else
            1.055 * std.math.pow(f32, clamped, 1.0 / 2.4) - 0.055;
        return @intFromFloat(std.math.clamp(encoded * 255.0 + 0.5, 0.0, 255.0));
    }
};

// Build a valid zlib stream using uncompressed (stored) deflate blocks.
// Produces larger output than a real compressor but works without the
// std.compress.flate internals that are incomplete in Zig 0.15.1.
fn zlibStored(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    const max_block: usize = 65535;
    const n_blocks: usize = if (data.len == 0) 1 else (data.len + max_block - 1) / max_block;
    // 2 zlib header + (5 per block header) + raw data + 4 Adler-32
    const out = try alloc.alloc(u8, 2 + n_blocks * 5 + data.len + 4);

    var pos: usize = 0;
    out[pos] = 0x78; out[pos + 1] = 0x01; pos += 2; // CMF=deflate CINFO=0, FLG

    var offset: usize = 0;
    var done = false;
    while (!done) {
        const end = @min(offset + max_block, data.len);
        const chunk = data[offset..end];
        const len: u16 = @intCast(chunk.len);
        done = (end == data.len);
        out[pos] = if (done) 0x01 else 0x00; pos += 1;        // BFINAL | BTYPE=00
        std.mem.writeInt(u16, out[pos..][0..2], len, .little); pos += 2;
        std.mem.writeInt(u16, out[pos..][0..2], ~len, .little); pos += 2;
        @memcpy(out[pos..][0..chunk.len], chunk);
        pos += chunk.len;
        offset = end;
    }

    // Adler-32 over uncompressed data
    var s1: u32 = 1;
    var s2: u32 = 0;
    for (data) |b| {
        s1 = (s1 + b) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    std.mem.writeInt(u32, out[pos..][0..4], (s2 << 16) | s1, .big);

    return out;
}

fn pngChunk(w: *std.Io.Writer, tag: *const [4]u8, data: []const u8) !void {
    var hdr: [4]u8 = undefined;
    std.mem.writeInt(u32, &hdr, @intCast(data.len), .big);
    try w.writeAll(&hdr);
    try w.writeAll(tag);
    try w.writeAll(data);
    std.mem.writeInt(u32, &hdr, pngCrc(tag, data), .big);
    try w.writeAll(&hdr);
}

fn pngCrc(tag: []const u8, data: []const u8) u32 {
    var c: u32 = 0xFFFFFFFF;
    for (tag) |b| c = pngCrcStep(c, b);
    for (data) |b| c = pngCrcStep(c, b);
    return c ^ 0xFFFFFFFF;
}

fn pngCrcStep(c: u32, b: u8) u32 {
    var v = c ^ b;
    for (0..8) |_| v = if (v & 1 != 0) (v >> 1) ^ 0xEDB88320 else v >> 1;
    return v;
}
