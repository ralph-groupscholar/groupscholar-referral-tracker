const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printHelp();
        return;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "help")) {
        try printHelp();
        return;
    } else if (std.mem.eql(u8, cmd, "init-db")) {
        try initDb(allocator);
        return;
    } else if (std.mem.eql(u8, cmd, "add-referral")) {
        try addReferral(allocator, args[2..]);
        return;
    } else if (std.mem.eql(u8, cmd, "list-referrals")) {
        try listReferrals(allocator, args[2..]);
        return;
    } else if (std.mem.eql(u8, cmd, "summary")) {
        try summary(allocator, args[2..]);
        return;
    } else if (std.mem.eql(u8, cmd, "partner-health")) {
        try partnerHealth(allocator, args[2..]);
        return;
    } else if (std.mem.eql(u8, cmd, "partner-alerts")) {
        try partnerAlerts(allocator, args[2..]);
        return;
    }

    std.debug.print("Unknown command: {s}\n", .{cmd});
    try printHelp();
}

fn printHelp() !void {
    const out = std.fs.File.stdout().deprecatedWriter();
    try out.writeAll(
        "Group Scholar Referral Tracker\n\n" ++
            "Usage:\n" ++
        "  gs-referral-tracker help\n" ++
        "  gs-referral-tracker init-db\n" ++
        "  gs-referral-tracker add-referral --partner <name> --scholar <name> --channel <channel> --date <YYYY-MM-DD> [--sector <sector>] [--region <region>] [--status <status>] [--notes <text>]\n" ++
        "  gs-referral-tracker list-referrals [--limit <n>]\n" ++
        "  gs-referral-tracker summary [--since <YYYY-MM-DD>]\n" ++
        "  gs-referral-tracker partner-health [--since <YYYY-MM-DD>] [--status <status>] [--limit <n>]\n" ++
        "  gs-referral-tracker partner-alerts [--stale-days <n>] [--status <status>] [--as-of <YYYY-MM-DD>] [--limit <n>]\n\n" ++
        "Environment:\n" ++
        "  DATABASE_URL must be set to the production Postgres connection string.\n" ++
        "Notes:\n" ++
        "  Commands shell out to psql, so ensure psql is available.\n"
    );
}

fn initDb(allocator: Allocator) !void {
    try runPsqlFile(allocator, "sql/001_init.sql");
    try runPsqlFile(allocator, "sql/002_seed.sql");
    std.debug.print("Database initialized and seeded.\n", .{});
}

fn addReferral(allocator: Allocator, args: []const []const u8) !void {
    var partner: ?[]const u8 = null;
    var scholar: ?[]const u8 = null;
    var channel: ?[]const u8 = null;
    var date: ?[]const u8 = null;
    var sector: []const u8 = "Unknown";
    var region: []const u8 = "Unknown";
    var status: []const u8 = "active";
    var notes: []const u8 = "";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--partner") and i + 1 < args.len) {
            i += 1;
            partner = args[i];
        } else if (std.mem.eql(u8, arg, "--scholar") and i + 1 < args.len) {
            i += 1;
            scholar = args[i];
        } else if (std.mem.eql(u8, arg, "--channel") and i + 1 < args.len) {
            i += 1;
            channel = args[i];
        } else if (std.mem.eql(u8, arg, "--date") and i + 1 < args.len) {
            i += 1;
            date = args[i];
        } else if (std.mem.eql(u8, arg, "--sector") and i + 1 < args.len) {
            i += 1;
            sector = args[i];
        } else if (std.mem.eql(u8, arg, "--region") and i + 1 < args.len) {
            i += 1;
            region = args[i];
        } else if (std.mem.eql(u8, arg, "--status") and i + 1 < args.len) {
            i += 1;
            status = args[i];
        } else if (std.mem.eql(u8, arg, "--notes") and i + 1 < args.len) {
            i += 1;
            notes = args[i];
        } else {
            std.debug.print("Unknown or incomplete flag: {s}\n", .{arg});
            return;
        }
    }

    if (partner == null or scholar == null or channel == null or date == null) {
        std.debug.print("Missing required flags.\n", .{});
        try printHelp();
        return;
    }

    const sql = try buildAddReferralSql(allocator, partner.?, scholar.?, channel.?, date.?, sector, region, status, notes);
    defer allocator.free(sql);
    try runPsqlCommand(allocator, sql);
    std.debug.print("Referral logged.\n", .{});
}

fn listReferrals(allocator: Allocator, args: []const []const u8) !void {
    var limit: usize = 25;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--limit") and i + 1 < args.len) {
            i += 1;
            limit = try std.fmt.parseInt(usize, args[i], 10);
        } else {
            std.debug.print("Unknown or incomplete flag: {s}\n", .{arg});
            return;
        }
    }

    const sql = try std.fmt.allocPrint(
        allocator,
        "select r.referral_id, p.name as partner, r.scholar_name, r.channel, r.referral_date, coalesce(r.notes, '') " ++
            "from gs_referral_tracker.referral r join gs_referral_tracker.partner p on r.partner_id = p.partner_id " ++
            "order by r.referral_date desc, r.referral_id desc limit {d};",
        .{limit},
    );
    defer allocator.free(sql);
    try runPsqlCommand(allocator, sql);
}

fn summary(allocator: Allocator, args: []const []const u8) !void {
    var since: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--since") and i + 1 < args.len) {
            i += 1;
            since = args[i];
        } else {
            std.debug.print("Unknown or incomplete flag: {s}\n", .{arg});
            return;
        }
    }

    const sql = if (since) |since_date| blk: {
        const since_esc = try escapeSqlLiteral(allocator, since_date);
        defer allocator.free(since_esc);
        break :blk try std.fmt.allocPrint(
            allocator,
            "select p.name, count(*) as referrals, min(r.referral_date) as first_referral, max(r.referral_date) as last_referral " ++
                "from gs_referral_tracker.referral r join gs_referral_tracker.partner p on r.partner_id = p.partner_id " ++
                "where r.referral_date >= '{s}' " ++
                "group by p.name order by referrals desc, p.name;",
            .{since_esc},
        );
    } else blk: {
        break :blk try std.fmt.allocPrint(
            allocator,
            "select p.name, count(*) as referrals, min(r.referral_date) as first_referral, max(r.referral_date) as last_referral " ++
                "from gs_referral_tracker.referral r join gs_referral_tracker.partner p on r.partner_id = p.partner_id " ++
                "group by p.name order by referrals desc, p.name;",
            .{},
        );
    };
    defer allocator.free(sql);
    try runPsqlCommand(allocator, sql);
}

fn partnerHealth(allocator: Allocator, args: []const []const u8) !void {
    var since: ?[]const u8 = null;
    var status: ?[]const u8 = null;
    var limit: usize = 25;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--since") and i + 1 < args.len) {
            i += 1;
            since = args[i];
        } else if (std.mem.eql(u8, arg, "--status") and i + 1 < args.len) {
            i += 1;
            status = args[i];
        } else if (std.mem.eql(u8, arg, "--limit") and i + 1 < args.len) {
            i += 1;
            limit = try std.fmt.parseInt(usize, args[i], 10);
        } else {
            std.debug.print("Unknown or incomplete flag: {s}\n", .{arg});
            return;
        }
    }

    const sql = try buildPartnerHealthSql(allocator, since, status, limit);
    defer allocator.free(sql);
    try runPsqlCommand(allocator, sql);
}

fn partnerAlerts(allocator: Allocator, args: []const []const u8) !void {
    var status: ?[]const u8 = null;
    var stale_days: i64 = 30;
    var limit: usize = 25;
    var as_of: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--status") and i + 1 < args.len) {
            i += 1;
            status = args[i];
        } else if (std.mem.eql(u8, arg, "--stale-days") and i + 1 < args.len) {
            i += 1;
            stale_days = try std.fmt.parseInt(i64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--as-of") and i + 1 < args.len) {
            i += 1;
            as_of = args[i];
        } else if (std.mem.eql(u8, arg, "--limit") and i + 1 < args.len) {
            i += 1;
            limit = try std.fmt.parseInt(usize, args[i], 10);
        } else {
            std.debug.print("Unknown or incomplete flag: {s}\n", .{arg});
            return;
        }
    }

    const sql = try buildPartnerAlertsSql(allocator, status, stale_days, limit, as_of);
    defer allocator.free(sql);
    try runPsqlCommand(allocator, sql);
}

fn buildAddReferralSql(
    allocator: Allocator,
    partner: []const u8,
    scholar: []const u8,
    channel: []const u8,
    date: []const u8,
    sector: []const u8,
    region: []const u8,
    status: []const u8,
    notes: []const u8,
) ![]u8 {
    const partner_esc = try escapeSqlLiteral(allocator, partner);
    const scholar_esc = try escapeSqlLiteral(allocator, scholar);
    const channel_esc = try escapeSqlLiteral(allocator, channel);
    const date_esc = try escapeSqlLiteral(allocator, date);
    const sector_esc = try escapeSqlLiteral(allocator, sector);
    const region_esc = try escapeSqlLiteral(allocator, region);
    const status_esc = try escapeSqlLiteral(allocator, status);
    const notes_esc = try escapeSqlLiteral(allocator, notes);
    defer allocator.free(partner_esc);
    defer allocator.free(scholar_esc);
    defer allocator.free(channel_esc);
    defer allocator.free(date_esc);
    defer allocator.free(sector_esc);
    defer allocator.free(region_esc);
    defer allocator.free(status_esc);
    defer allocator.free(notes_esc);

    return std.fmt.allocPrint(
        allocator,
        "with upsert_partner as (" ++
            "insert into gs_referral_tracker.partner (name, sector, region, status) " ++
            "values ('{s}', '{s}', '{s}', '{s}') " ++
            "on conflict (name) do update set sector = excluded.sector, region = excluded.region, status = excluded.status " ++
            "returning partner_id" ++
            ") " ++
            "insert into gs_referral_tracker.referral (partner_id, scholar_name, channel, referral_date, notes) " ++
            "select partner_id, '{s}', '{s}', '{s}', nullif('{s}', '') from upsert_partner;",
        .{ partner_esc, sector_esc, region_esc, status_esc, scholar_esc, channel_esc, date_esc, notes_esc },
    );
}

fn buildPartnerHealthSql(
    allocator: Allocator,
    since: ?[]const u8,
    status: ?[]const u8,
    limit: usize,
) ![]u8 {
    var sql = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer sql.deinit(allocator);

    try sql.appendSlice(
        allocator,
        "select p.name, p.status, p.region, p.sector, " ++
            "count(r.referral_id) as referrals, max(r.referral_date) as last_referral " ++
            "from gs_referral_tracker.partner p " ++
            "left join gs_referral_tracker.referral r on r.partner_id = p.partner_id",
    );

    if (since) |since_date| {
        const since_esc = try escapeSqlLiteral(allocator, since_date);
        defer allocator.free(since_esc);
        try sql.appendSlice(allocator, " and r.referral_date >= '");
        try sql.appendSlice(allocator, since_esc);
        try sql.appendSlice(allocator, "'");
    }

    if (status) |status_value| {
        const status_esc = try escapeSqlLiteral(allocator, status_value);
        defer allocator.free(status_esc);
        try sql.appendSlice(allocator, " where p.status = '");
        try sql.appendSlice(allocator, status_esc);
        try sql.appendSlice(allocator, "'");
    }

    try sql.appendSlice(
        allocator,
        " group by p.name, p.status, p.region, p.sector " ++
            "order by last_referral desc nulls last, referrals desc, p.name limit ",
    );
    try sql.writer(allocator).print("{d};", .{limit});

    return sql.toOwnedSlice(allocator);
}

fn buildPartnerAlertsSql(
    allocator: Allocator,
    status: ?[]const u8,
    stale_days: i64,
    limit: usize,
    as_of: ?[]const u8,
) ![]u8 {
    var sql = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer sql.deinit(allocator);

    const as_of_expr = if (as_of) |as_of_date| blk: {
        const as_of_esc = try escapeSqlLiteral(allocator, as_of_date);
        defer allocator.free(as_of_esc);
        break :blk try std.fmt.allocPrint(allocator, "'{s}'::date", .{as_of_esc});
    } else blk: {
        break :blk try std.fmt.allocPrint(allocator, "current_date", .{});
    };
    defer allocator.free(as_of_expr);

    try sql.appendSlice(allocator, "select p.name, p.status, p.region, p.sector, ");
    try sql.appendSlice(allocator, "max(r.referral_date) as last_referral, ");
    try sql.appendSlice(allocator, as_of_expr);
    try sql.appendSlice(allocator, " - max(r.referral_date) as days_since ");
    try sql.appendSlice(
        allocator,
        "from gs_referral_tracker.partner p left join gs_referral_tracker.referral r on r.partner_id = p.partner_id",
    );

    if (status) |status_value| {
        const status_esc = try escapeSqlLiteral(allocator, status_value);
        defer allocator.free(status_esc);
        try sql.appendSlice(allocator, " where p.status = '");
        try sql.appendSlice(allocator, status_esc);
        try sql.appendSlice(allocator, "'");
    }

    try sql.appendSlice(allocator, " group by p.name, p.status, p.region, p.sector");
    try sql.appendSlice(allocator, " having (max(r.referral_date) is null or (");
    try sql.appendSlice(allocator, as_of_expr);
    try sql.appendSlice(allocator, " - max(r.referral_date)) >= ");
    try sql.writer(allocator).print("{d})", .{stale_days});
    try sql.appendSlice(allocator, " order by days_since desc nulls last, p.name limit ");
    try sql.writer(allocator).print("{d};", .{limit});

    return sql.toOwnedSlice(allocator);
}

fn escapeSqlLiteral(allocator: Allocator, value: []const u8) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    for (value) |ch| {
        if (ch == '\'') {
            try buffer.append(allocator, '\'');
        }
        try buffer.append(allocator, ch);
    }

    return buffer.toOwnedSlice(allocator);
}

fn runPsqlCommand(allocator: Allocator, sql: []const u8) !void {
    const db_url = try getDatabaseUrl(allocator);
    defer allocator.free(db_url);

    var argv = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer argv.deinit(allocator);

    try argv.append(allocator, "psql");
    try argv.append(allocator, "-d");
    try argv.append(allocator, db_url);
    try argv.append(allocator, "-v");
    try argv.append(allocator, "ON_ERROR_STOP=1");
    try argv.append(allocator, "-A");
    try argv.append(allocator, "-F");
    try argv.append(allocator, "\t");
    try argv.append(allocator, "-c");
    try argv.append(allocator, sql);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
    });

    try std.fs.File.stdout().writeAll(result.stdout);
    try std.fs.File.stderr().writeAll(result.stderr);

    if (result.term.Exited != 0) {
        return error.PsqlFailed;
    }
}

fn runPsqlFile(allocator: Allocator, path: []const u8) !void {
    const db_url = try getDatabaseUrl(allocator);
    defer allocator.free(db_url);

    var argv = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer argv.deinit(allocator);

    try argv.append(allocator, "psql");
    try argv.append(allocator, "-d");
    try argv.append(allocator, db_url);
    try argv.append(allocator, "-v");
    try argv.append(allocator, "ON_ERROR_STOP=1");
    try argv.append(allocator, "-f");
    try argv.append(allocator, path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
    });

    try std.fs.File.stdout().writeAll(result.stdout);
    try std.fs.File.stderr().writeAll(result.stderr);

    if (result.term.Exited != 0) {
        return error.PsqlFailed;
    }
}

fn getDatabaseUrl(allocator: Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "DATABASE_URL") catch {
        std.debug.print("DATABASE_URL is not set.\n", .{});
        return error.MissingDatabaseUrl;
    };
}

test "escapeSqlLiteral doubles single quotes" {
    const allocator = std.testing.allocator;
    const result = try escapeSqlLiteral(allocator, "O'Neil");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("O''Neil", result);
}

test "buildAddReferralSql includes required values" {
    const allocator = std.testing.allocator;
    const sql = try buildAddReferralSql(allocator, "Partner A", "Scholar B", "Email", "2025-01-10", "Education", "Midwest", "active", "Warm intro");
    defer allocator.free(sql);
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "Partner A"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "Scholar B"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "2025-01-10"));
}

test "buildPartnerHealthSql includes filters and limit" {
    const allocator = std.testing.allocator;
    const sql = try buildPartnerHealthSql(allocator, "2025-11-01", "active", 10);
    defer allocator.free(sql);
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "referral_date >= '2025-11-01'"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "where p.status = 'active'"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "limit 10"));
}

test "buildPartnerAlertsSql includes as-of, stale filter, and status" {
    const allocator = std.testing.allocator;
    const sql = try buildPartnerAlertsSql(allocator, "active", 45, 12, "2026-01-10");
    defer allocator.free(sql);
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "where p.status = 'active'"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "'2026-01-10'::date - max"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, ">= 45"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sql, 1, "limit 12"));
}
