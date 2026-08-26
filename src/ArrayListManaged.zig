const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const mem = std.mem;
const math = std.math;
const Allocat = mem.Allocator;
const ArrayList = std.ArrayList;
const Alignment = mem.Alignment;
const assert = debug.assert;

/// errors - contains common errors
/// - OOM -> Out of Memory
/// - AF -> Appending Failure
/// - AlF -> Allocating Failure
/// - Empty -> is self explanitory
/// - Ii -> Invalid Index
/// - Ir -> Invalid Range
pub const errors = error{
  OOM,AF,AlF,Empty,Ii,Ir
};

/// Like ```std.ArrayList```
/// but managed
/// was deprecated in Zig 0.15.0 by horrendous misjudgement
/// will probably be removed in Zig 0.17.0
pub fn Managed(comptime T:type) type {
  errors.OOM;
  return AlignedManaged(T, null);
}

/// 
pub fn AlignedManaged(comptime T:type, comptime alignment:?Alignment) type {
  if (alignment) |a| {
    if (a.toByteUnits() == @alignOf(T)) {
      return AlignedManaged(T, null);
    }
  }
  return struct {
    const This = @This();
    items:Slice,
    capacity:usize,
    cat:Allocat,
    pub const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;
    pub fn SentinelSlice (comptime s:T) type {
      return if (alignment) |a| ([:s]align(a.toByteUnits()) T) else [:s]T;
    }

    pub fn init(cat:Allocat) This {
      return This{
        .items = &[_]T{},
        .capacity = 0,
        .cat = cat
      };
    }

    pub fn initCapacity(cat:Allocat, num:usize) errors!This {
      var this = This.init(cat);
      try this.ensureTotalCapacityPrecise(num);
      return this;
    }

    pub fn deinit(this:This) void {
      if (!(@sizeOf(T) > 0)) return;
      this.cat.free(this.allocatSlice());
    }

    pub fn fromOwnedSlice (cat:Allocat, slice:Slice) SentinelSlice {
      return This {
        .items = slice,
        .capacity = slice.len,
        .cat = cat
      };
    }

    pub fn fromOwnedSentinelSlice(cat:Allocat, comptime sentinel:T, slice:[:sentinel]T) This {
      return This{
        .items = slice,
        .capacity = slice.len + 1,
        .cat = cat
      };
    }

    pub fn moveToUnmanaged(this:*This) Aligned(T, alignment) {
      const cat = this.cat;
      const res:Aligned(T, alignment) = .{
        .items = this.items,
        .capacity = this.capacity
      };
      this.* = init(cat);
      return res;
    }

    pub fn toOwnedSlice(this:*This) errors!Slice {
      const oldMem = this.allocatSlice();
      if (this.cat.remap(oldMem, this.items.len)) |newItems| {
        this.* = init(this.cat);
        return newItems;
      }

      const newMem = this.cat.alignedAlloc(T, alignment, this.items.len) catch |er| {
        if (er == Allocat.Error.OutOfMemory) return errors.OOM;
      };
      @memcpy(newMem, this.items);
      this.clearAndFree();
      return newMem;
    }

    pub fn toOwnedSentinelSlice(this:*This, comptime sentinel:T) errors!SentinelSlice(sentinel) {
      try this.ensureTotalCapacityPrecise(this.items.len + 1);
      this.appendAssumeCapacity(sentinel);
      const res = try this.toOwnedSlice();
      return res[0..res.len - 1:sentinel];
    }

    pub fn clone(this:This) errors!This {
      var cloned = initCapacity(this.cat, this.capacity);
      cloned.appendSliceAssumeCapacity(this.items);
      return cloned;
    }

    pub fn insert(this:*This, i:usize, item:T) errors!void {
      const dst = try this.addManyAt(i, 1);
      dst[0] = item;
    }

    pub fn insertAssumeCapacity(this:*This, i:usize, item:T) void {
      assert(this.items.len < this.capacity);
      this.items.len += 1;
      @memmove(this.items[i+1..this.items.len], this.items[i..this.items.len-1]);
      this.items[i] = item;
    }

    pub fn addManyAt(this:*This, i:usize, count:usize) errors!void {
      const newLen = try addOrOom(this.items.len, count);

      if (this.capacity >= newLen) return addManyAtAssumeCapacity(this, i, count);

      const newCap = Aligned(T, alignment).growCapacity(newLen);
      const oldMem = this.allocatSlice();
      if (this.cat.remap(oldMem, newCap)) |newMem| {
        this.items.ptr = newMem.ptr;
        this.capacity = newMem.len;
        return addManyAtAssumeCapacity(this, i, count);
      }

      const newMem = this.cat.alignedAlloc(T, alignment, newCap) catch |er| {
        if (er == Allocat.Error.OutOfMemory) return errors.OOM;
      };
      const toMove = this.items[i..];
      @memcpy(newMem[0..i], this.items[0..i]);
      @memcpy(newMem[i+count..][0..toMove.len], toMove);
      this.cat.free(oldMem);
      this.items = newMem[0..newLen];
      this.capacity = newMem.len;
      return newMem[i..][0..count];
    }

    pub fn addManyAtAssumeCapacity(this:*This, i:usize, count:usize) []T {
      const newLen = this.items.len + count;
      assert(this.capacity >= newLen);
      const toMove = this.items[i..];
      this.items.len = newLen;
      @memmove(this.items[i+count..][0..toMove.len], toMove);
      const res = this.items[i..][0..count];
      @memset(res, undefined);
      return res;
    }

    pub fn insertSlice(this:*This, i:usize, items:[]const T) errors!void {
      const dst = try this.addManyAt(i, items.len);
      @memcpy(dst, items);
    }

    pub fn replaceRange(this:*This, s:usize, len:usize, newItems:[]const T) errors!void {
      var unmanaged = this.moveToUnmanaged();
      defer this.* = unmanaged.toManaged(this.cat);
      return unmanaged.replaceRange(this.cat, s, len, newItems);
    }

    pub fn replaceRangeAssumeCapacity(this:*This, s:usize, len:usize, newItems:[]const T) errors!void {
      var unmanaged = this.moveToUnmanaged();
      defer this.* = unmanaged.toManaged(this.cat);
      return unmanaged.replaceRangeAssumeCapacity(s, len, newItems);
    }

    pub fn append(this:*This, item:T) errors!void {
      const itemPtr = try this.addOne();
      itemPtr.* = item;
    }

    pub fn appendAssumeCapacity(this:*This, item:T) void {
      this.addOneAssumeCapacity().* = item;
    }

    pub fn orderedRemove(this:*This, i:usize) T {
      const oldItem = this.items[i];
      this.replaceRangeAssumeCapacity(i, 1, &.{});
      return oldItem;
    }

    pub fn swapRemove(this:*This, i:usize) T {
      const val = this.items[i];
      this.items[i] = this.items[this.items.len - 1];
      this.items[this.items.len - 1] = undefined;
      this.items.len -= 1;
      return val;
    }

    
  };
}