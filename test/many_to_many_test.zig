const std = @import("std");
const orm = @import("zig-orm");

test "many-to-many relationships" {
    // Define models
    const Student = struct {
        id: i64,
        name: []const u8,
    };

    const Course = struct {
        id: i64,
        title: []const u8,
    };

    const Enrollment = struct {
        id: i64,
        student_id: i64,
        course_id: i64,
    };

    const Students = orm.Table(Student, "students");
    const Courses = orm.Table(Course, "courses");
    const Enrollments = orm.Table(Enrollment, "enrollments");
    const Repo = orm.Repo(orm.sqlite.SQLite);

    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    // Setup tables
    try repo.adapter.exec("CREATE TABLE students (id INTEGER PRIMARY KEY, name TEXT)");
    try repo.adapter.exec("CREATE TABLE courses (id INTEGER PRIMARY KEY, title TEXT)");
    try repo.adapter.exec("CREATE TABLE enrollments (id INTEGER PRIMARY KEY, student_id INTEGER, course_id INTEGER)");

    // Insert students
    {
        var q = try Students.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .name = "Alice" });
        try q.add(.{ .id = 2, .name = "Bob" });
        try repo.insert(q);
    }

    // Insert courses
    {
        var q = try Courses.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .title = "Math 101" });
        try q.add(.{ .id = 2, .title = "Physics 201" });
        try q.add(.{ .id = 3, .title = "Chemistry 301" });
        try repo.insert(q);
    }

    // Insert enrollments (Alice in Math and Physics, Bob in Physics and Chemistry)
    {
        var q = try Enrollments.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .student_id = 1, .course_id = 1 });
        try q.add(.{ .id = 2, .student_id = 1, .course_id = 2 });
        try q.add(.{ .id = 3, .student_id = 2, .course_id = 2 });
        try q.add(.{ .id = 4, .student_id = 2, .course_id = 3 });
        try repo.insert(q);
    }

    // Test: Load courses for Alice
    {
        // Step 1: Get enrollments for Alice
        const enrollments = try repo.findAllBy(Enrollments, .{ .student_id = 1 });
        defer std.testing.allocator.free(enrollments);

        try std.testing.expectEqual(@as(usize, 2), enrollments.len);

        // Step 2: Extract course IDs
        const course_ids = [_]i64{ enrollments[0].course_id, enrollments[1].course_id };

        // Step 3: Load courses in one query
        var q = try orm.from(Courses, std.testing.allocator);
        defer q.deinit();
        _ = try q.whereIn("id", &course_ids);

        const courses = try repo.all(q);
        defer std.testing.allocator.free(courses);
        defer {
            for (courses) |c| std.testing.allocator.free(c.title);
        }

        try std.testing.expectEqual(@as(usize, 2), courses.len);
        // Verify we got Math and Physics
        var found_math = false;
        var found_physics = false;
        for (courses) |c| {
            if (std.mem.eql(u8, c.title, "Math 101")) found_math = true;
            if (std.mem.eql(u8, c.title, "Physics 201")) found_physics = true;
        }
        try std.testing.expect(found_math);
        try std.testing.expect(found_physics);
    }

    // Test: Load students for Physics course
    {
        // Step 1: Get enrollments for Physics
        const enrollments = try repo.findAllBy(Enrollments, .{ .course_id = 2 });
        defer std.testing.allocator.free(enrollments);

        try std.testing.expectEqual(@as(usize, 2), enrollments.len);

        // Step 2: Extract student IDs
        const student_ids = [_]i64{ enrollments[0].student_id, enrollments[1].student_id };

        // Step 3: Load students in one query
        var q = try orm.from(Students, std.testing.allocator);
        defer q.deinit();
        _ = try q.whereIn("id", &student_ids);

        const students = try repo.all(q);
        defer std.testing.allocator.free(students);
        defer {
            for (students) |s| std.testing.allocator.free(s.name);
        }

        try std.testing.expectEqual(@as(usize, 2), students.len);
        // Verify we got Alice and Bob
        var found_alice = false;
        var found_bob = false;
        for (students) |s| {
            if (std.mem.eql(u8, s.name, "Alice")) found_alice = true;
            if (std.mem.eql(u8, s.name, "Bob")) found_bob = true;
        }
        try std.testing.expect(found_alice);
        try std.testing.expect(found_bob);
    }

    // Test: Empty association
    {
        const enrollments = try repo.findAllBy(Enrollments, .{ .student_id = 999 });
        defer std.testing.allocator.free(enrollments);

        try std.testing.expectEqual(@as(usize, 0), enrollments.len);
    }
}
