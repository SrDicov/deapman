const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

const usage =
    \\deapman-thin — content-hash helper for deapman
    \\
    \\Usage:
\\  deapman-thin inventory <label> <dir>...   walk dirs, print TSV: label<TAB>path<TAB>size<TAB>sha256
\\  deapman-thin verify <file> <sha256>       exit 0 if hash matches, 1 otherwise
\\  deapman-thin dups <inventory.tsv>         dup report over app<TAB>path<TAB>size<TAB>sha256 (mirrors _deapman_dedup awk)
\\  deapman-thin -h | -v
    \\
;

fn shaFile(path: []const u8, out_hex: *[Sha256.digest_length * 2]u8) !u64 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var h = Sha256.init(.{});
    var buf: [65536]u8 = undefined;
    var total: u64 = 0;
    while (true) {
        const n = try f.read(&buf);
        if (n == 0) break;
        h.update(buf[0..n]);
        total += n;
    }
    var digest: [Sha256.digest_length]u8 = undefined;
    h.final(&digest);
    const hex = "0123456789abcdef";
    for (digest, 0..) |b, i| {
        out_hex[i * 2] = hex[b >> 4];
        out_hex[i * 2 + 1] = hex[b & 0x0f];
    }
    return total;
}

fn inventory(alloc: std.mem.Allocator, label: []const u8, dirs: []const []const u8) !void {
    const out = std.io.getStdOut().writer();
    for (dirs) |dir_path| {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            std.log.err("cannot open dir {s}: {}", .{ dir_path, err });
            continue;
        };
        defer dir.close();
        var walker = try dir.walk(alloc);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            const full = try std.fs.path.join(alloc, &.{ dir_path, entry.path });
            defer alloc.free(full);
            var hex: [Sha256.digest_length * 2]u8 = undefined;
            const size = shaFile(full, &hex) catch |err| {
                std.log.err("cannot hash {s}: {}", .{ full, err });
                continue;
            };
            try out.print("{s}\t{s}\t{d}\t{s}\n", .{ label, entry.path, size, hex });
        }
    }
}

fn verify(file: []const u8, expected: []const u8) !u8 {
    var hex: [Sha256.digest_length * 2]u8 = undefined;
    const f = std.fs.cwd().openFile(file, .{}) catch {
        std.debug.print("deapman-thin: missing file: {s}\n", .{file});
        return 1;
    };
    f.close();
    _ = try shaFile(file, &hex);
    if (std.ascii.eqlIgnoreCase(&hex, expected)) {
        std.debug.print("ok {s}\n", .{file});
        return 0;
    }
    std.debug.print("MISMATCH {s}\n  got {s}\n  exp {s}\n", .{ file, hex, expected });
    return 1;
}

// dups threshold: mirrors DEAPMAN_MIN_THIN_BYTES default in modules/deapman-dedup.am.
// Kept constant for now; a future change will read $DEAPMAN_MIN_THIN_BYTES.
const min_thin_bytes: u64 = 32768;
// Display cap: mirrors the `head -40` tail of the _deapman_dedup pipeline.
// TOTAL always covers every qualifying group, even when dup lines are capped.
const max_dup_lines: u32 = 40;

const DupGroup = struct {
    count: u64,
    bytes: u64, // last size seen for the hash (awk: bytes[h]=sz overwrites)
    apps: std.ArrayList(u8), // " app1 app2..." in file order (pipeline: hash-sorted order)
};

// dups <inventory.tsv>: byte-identical reprint of the _deapman_dedup awk report:
//   dup <n>× <bytes> B  sha:<12hex>  en:<space-separated apps>
//   TOTAL: <d> ficheros duplicados, ahorro potencial <s> B
// Only hashes with n>1 and size>=min_thin_bytes qualify. Dup-line order follows
// hash-map iteration (like awk's `for (h in n)`), so it is NOT sorted; TOTAL is
// always printed last. Returns 1 when the file cannot be opened/read.
fn dups(alloc: std.mem.Allocator, path: []const u8) !u8 {
    const f = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("deapman-thin: cannot open {s}: {}\n", .{ path, err });
        return 1;
    };
    defer f.close();
    const data = f.readToEndAlloc(alloc, 1 << 31) catch |err| {
        std.debug.print("deapman-thin: cannot read {s}: {}\n", .{ path, err });
        return 1;
    };
    defer alloc.free(data);

    var groups = std.StringHashMap(DupGroup).init(alloc);
    defer {
        var it = groups.iterator();
        while (it.next()) |e| {
            alloc.free(e.key_ptr.*);
            e.value_ptr.apps.deinit();
        }
        groups.deinit();
    }

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimRight(u8, raw, "\r");
        if (line.len == 0) continue;
        var cols = std.mem.splitScalar(u8, line, '\t');
        const app = cols.next() orelse continue;
        _ = cols.next() orelse continue; // path may contain spaces; tabs are the separator
        const size_s = cols.next() orelse continue;
        const hash = cols.next() orelse continue;
        if (hash.len == 0) continue;
        // awk `sz=$2+0`: non-numeric sizes coerce to 0 and get filtered below.
        const size = std.fmt.parseInt(u64, std.mem.trim(u8, size_s, " "), 10) catch 0;
        const key = try alloc.dupe(u8, hash);
        const gop = try groups.getOrPut(key);
        if (gop.found_existing) {
            alloc.free(key);
        } else {
            gop.value_ptr.* = .{ .count = 0, .bytes = 0, .apps = std.ArrayList(u8).init(alloc) };
        }
        const g = gop.value_ptr;
        g.count += 1;
        g.bytes = size;
        try g.apps.appendSlice(" ");
        try g.apps.appendSlice(app);
    }

    const out = std.io.getStdOut().writer();
    var shown: u32 = 0;
    var ndups: u64 = 0;
    var saved: u64 = 0;
    var it = groups.iterator();
    while (it.next()) |e| {
        const g = e.value_ptr;
        if (g.count > 1 and g.bytes >= min_thin_bytes) {
            ndups += 1;
            saved += g.bytes * (g.count - 1);
            if (shown < max_dup_lines) {
                shown += 1;
                const key: []const u8 = e.key_ptr.*;
                try out.print("dup {d}× {d} B  sha:{s}  en:{s}\n", .{
                    g.count, g.bytes, key[0..@min(12, key.len)], g.apps.items,
                });
            }
        }
    }
    try out.print("TOTAL: {d} ficheros duplicados, ahorro potencial {d} B\n", .{ ndups, saved });
    return 0;
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len < 2) {
        std.debug.print("{s}", .{usage});
        return 2;
    }
    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "help")) {
        std.debug.print("{s}", .{usage});
        return 0;
    }
    if (std.mem.eql(u8, cmd, "-v") or std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "version")) {
        std.debug.print("deapman-thin 0.1.0\n", .{});
        return 0;
    }
    if (std.mem.eql(u8, cmd, "inventory")) {
        if (args.len < 4) {
            std.debug.print("usage: deapman-thin inventory <label> <dir>...\n", .{});
            return 2;
        }
        try inventory(alloc, args[2], args[3..]);
        return 0;
    }
    if (std.mem.eql(u8, cmd, "verify")) {
        if (args.len != 4) {
            std.debug.print("usage: deapman-thin verify <file> <sha256>\n", .{});
            return 2;
        }
        return try verify(args[2], args[3]);
    }
    if (std.mem.eql(u8, cmd, "dups")) {
        if (args.len != 3) {
            std.debug.print("usage: deapman-thin dups <inventory.tsv>\n", .{});
            return 2;
        }
        return try dups(alloc, args[2]);
    }
    std.debug.print("unknown command: {s}\n{s}", .{ cmd, usage });
    return 2;
}
