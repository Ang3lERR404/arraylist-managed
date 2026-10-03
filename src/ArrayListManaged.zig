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

const assert = debug.assert;

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

    const gAOps = enum{
      slice,
      slicedSentinel,
      one,
      many,
      normal,
      assume,
      range,
      rAssume
    };
    const gOps = enum{
      slice,
      slicedSentinel
    };
    const igOps = enum{
      one,
      many,
      slice
    };
    const agOps = enum{
      normal,
      assume
    };
    const apOps = enum{
      normal,
      assume,
      range,
      rAssume
    };

    pub fn from(this:*This, comptime method:gOps, args:anytype) This {
      _ = this;
      const tI = @typeInfo(@TypeOf(args));
      if (tI != .@"struct") @compileError("Expected args to be a struct, specifically a tuple, got: "++@typeName(@TypeOf(args)));
      if (!tI.@"struct".is_tuple) @compileError("Expected args to be a tuple, passed args was not.");
      return switch(method) {
        .slice => This{
          .items = args.slice,
          .cat = args.cat,
          .len = args.slice.len
        },
        .slicedSentinel => This{
          .items = args.slice,
          .len = args.slice.len + 1,
          .cat = args.cat
        }
      };
    }

    pub fn to(this:*This, comptime method:gOps, comptime args:anytype) errors!switch(method) {.slice => Slice, else => SentinelSlice(args.sent)} {
      return switch(method) {
        .slice => {
          const oM = this.allocatedSlice();
          if (this.cat.remap(oM, this.items.len)) |iotas| {
            this.* = .init(this.cat);
            return iotas;
          }

          const nM = try this.cat.alignedAlloc(t, alig, this.items.len);
          @memcpy(nM, this.items);
          this.clearAndFree();
          return nM;
        },
        .slicedSentinel => {
          try this.ensureLen(this.items.len + 1, .precise);
          this.append(.assume, args.sent);
          const res = try this.to(.slice);
          return res[0..:args.sent];
        }
      };
    }

    pub fn clone(this:This) errors!This {
      var cloned:This = try .initLen(this.cat, this.len);
      cloned.append(.assumeSlice, this.items);
      return cloned;
    }

    pub fn insert(this:*This, comptime method:igOps, i:usize, iota:switch(method){.one,.many => t, else=>[]t}) errors!void {
      switch(method) {
        .one => {
          const dst = try this.add(.manyAt, .{.i = i, .amnt = 1});
          dst[i] = iota;
        },
        .many => {
          assert(this.items.len < this.len);
          this.items.len += 1;
          @memmove(this.items[i+1..], this.items[i..]);
          this.items[i] = iota;
        },
        .slice => {
          const dst = try this.addManyAt(.normal, i, iota.len);
          @memcpy(dst, iota);
        }
      }
    }

    pub fn addManyAt(this:*This, comptime method:agOps, i:usize, count:usize) switch(method) {.normal => errors![]t, .assume => []t} {
      return switch (method) {
        .normal => {
          const nL = try This.addOrOom(this.items.len, count);
          if (this.len >= nL) return this.addManyAt(.assume, i, count);

          const nC = Array(t, alig).growBy(nL);
          const oM = this.allocatedSlice();
          if (this.cat.remap(oM, nC)) |qualia| {
            this.items.ptr = qualia.ptr;
            this.len = qualia.len;
            return this.addManyAt(.assume, i, count);
          }

          const qualia = try this.cat.alignedAlloc(t, alig, nC);
          const tM = this.items[i..];
          @memcpy(qualia[0..i], this.items[0..i]);
          @memcpy(qualia[i+count..][0..tM.len], tM);
          this.cat.free(oM);
          this.items = qualia[0..tM.len];
          this.len = qualia.len;
          return qualia[i..][0..count];
        },
        .assume => {
          const nL = this.items.len + count;
          assert(this.len >= nL);
          const tM = this.items[i..];
          this.items.len = nL;
          @memmove(this.items[i+count..][0..tM.len], tM);
          const res = this.items[i..][0..count];
          @memset(res, undefined);
          return res;
        }
      };
    }

    pub fn replaceRange(this:*This, comptime method:agOps, s:usize, e:usize, nIotas:[]const t) switch(method) {.normal => errors!void, else => void} {
      switch(method) {
        .normal => {
          try this.ensureLen(.normal, try This.addOrOom(this.items.len - e, nIotas.len));
          this.replaceRange(.assume, s, e, nIotas);
        },
        .assume => {
          assert(this.len - this.items.len >= nIotas.len -| e);
          const tail = this.items[s+e..];
          const vacd = this.items[this.items.len - (e -| nIotas.len)..];
          this.items.len = this.items.len - e + nIotas.len;
          @memmove(this.items[s+nIotas.len..], tail);
          @memcpy(this.items[s..][0..nIotas.len], nIotas);
          @memset(vacd, undefined);
        }
      }
    }

    pub fn append(this:*This, comptime method:apOps, iota:switch(method){.normal,.assume => t, .range,.rAssume => []t}) switch(method) {.normal,.range=>errors!void,else=>void} {

    }
  };
}