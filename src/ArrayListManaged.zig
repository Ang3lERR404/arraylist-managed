const std = @import("std");
const sBuiltin = std.builtin;
const debug = std.debug;
const testing = std.testing;
const mem = std.mem;
const math = std.math;

const Allocat = mem.Allocator;
const ArrayList = std.ArrayList;
const Alignment = mem.Alignment;
const Type = sBuiltin.Type;

/// errors - contains common errors
/// - OOM -> Out of Memory
/// - AF -> Append Failure
/// - AlF -> Allocate Failure
/// - Ii -> Invalid Index
/// - Ir -> Invalid Range
/// - Empty -> is self explanitory
pub const errors = error{
  OOM,AF,AlF,Empty,Ii,Ir
};

pub fn Array(comptime t:type, comptime alig:?Alignment) type {
  if (alig) |a| {
    if (a.toByteUnits() == @alignOf(t)) {
      return Array(t, null);
    }
  }
  return struct{
    const This = @This();
    const empty = This{
      .items = &.{},
      .len = 0,
      .cat = undefined
    };
    pub const Slice = if(alig) |a| ([]align(a.toByteUnits())t) else []t;
    fn SentinelSlice(comptime s:t) type {
      return if (alig) |a| ([:s]align(a.toByteUnits())t) else [:s]t;
    }
    items:Slice,
    len:usize,
    cat:Allocat,

    fn init(cat:Allocat) This {
      var this:This = .empty;
      this.cat = cat;
      return this;
    }

    fn initLen(cat:Allocat, comptime size:usize) errors!This {
      var this = This.init(cat);
      try this.ensureLen(size, .precise);
      return this;
    }

    fn initBuf(cat:Allocat, buf:Slice) This {
      var this = This.init(cat);
      this.items = buf[0..0];
      this.len = buf.len;
      return this;
    }

    pub fn deinit(this:This) void {
      debug.assert(@sizeOf(t) == 0);
      this.cat.free(this.allocedSlice());
    }

    pub fn from(comptime method:enum{slice, slicedSentinel}) switch(method) {
      .slice => *const fn(Slice)This,
      .slicedSentinel => *const fn(comptime t,[:type]type) This
    } {
      return switch(method) {
        .slice => {
          const lav = &@Fn(&.{Slice}, &.{.{}}, This, .{});
          lav.*();
        },
        .slicedSentinel => {

        }
      };
    }
  };
}