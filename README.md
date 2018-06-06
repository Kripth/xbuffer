xbuffer
=======

[![DUB Package](https://img.shields.io/dub/v/xbuffer.svg)](https://code.dlang.org/packages/xbuffer)
[![codecov](https://codecov.io/gh/nextcardgame/xbuffer/branch/master/graph/badge.svg)](https://codecov.io/gh/nextcardgame/xbuffer)
[![Build Status](https://travis-ci.org/nextcardgame/xbuffer.svg?branch=master)](https://travis-ci.org/nextcardgame/xbuffer)

A @nogc buffer that automatically grows when writing and frees its memory on destruction.

**Jump to**: [Buffer](#buffer), [Typed Buffer](#typed-buffer)

## Buffer

The `Buffer` class is located in `xbuffer.buffer` and is the base buffer class.
The buffer has a fixed chunk size that is used to expand it when more data is needed.

```d
Buffer buffer = new Buffer(4);

buffer.write(ushort(0));
assert(buffer.capacity == 4);

buffer.write(uint(1));
assert(buffer.capacity == 8);
```

The buffer can be also constructed using an array of data, the chunk size will be the length (in bytes) of that data.

```d
Buffer buffer = new Buffer([1, 2, 3, 4]);
assert(buffer.capacity == 16); // 4 * int.sizeof

buffer = new Buffer(cast(ubyte[])[1, 2, 3, 4]);
assert(buffer.capacity == 4);
```

**Jump to**: [data](#data), [writing](#writing), [reading](#reading), [peeking](#peeking)

### data

The buffer's data is stored as a `void[]` but can be converted to any fixed-size type using the `data` property.

```d
Buffer buffer = new Buffer([1, 2, 3]);
assert(buffer.data!int == [1, 2, 3]);
assert(buffer.data!ubyte == [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]); // on a little-endian system
```

The data property can also be used to assign an array of a fixed-size type to the buffer.
The chunk size of the buffer does not change.

```d
Buffer buffer = new Buffer(8);
buffer.data = [1, 2, 3];
buffer.data = cast(ubyte[])[1, 2, 3];
```

### writing

Data is written to the buffer using the `write` template.
It is possible to write any fixed-size type of data (even `struct`s).

Every write method is `pure`, `nothrow`, `@safe` and `@nogc`.

```d
Buffer buffer = new Buffer(16);

// an integer, using the system's endianness
buffer.write(1);

// a big-endian short
buffer.write!(Endian.bigEndian, short)(42);

// an array of integers, using the system's endianness
buffer.write([1, 2, 3]);

// an array of little-endian floats
buffer.write!(Endian.littleEndian)([0f, 1f, .5f]);
```

The operation of writing increases the data's length but doesn't increase the buffer's reading index;
this means that the written data can also be read/peeked in the same order it was written (see examples in next section).

### reading

Data is read from the buffer using the `read` template.

Every read method may throw a `BufferOverflowException` if there isn't enough data to read.
That's also the only reason why read methods are not `@nogc`.

```d
Buffer buffer = new Buffer(new ubyte[30]);

// an integer, using the system's endianness
buffer.read!int();

// a little-endian short
buffer.read!(Endian.littleEndian, short)();

// an array of 2 integers, using the system's endianness
buffer.read!(int[])(2);

// an array of 4 big-endian floats
buffer.read!(Endian.bigEndian, float[])(4);
```

The operation of reading increases the data's index but doesn't change the buffer's length.

```d
Buffer buffer = new Buffer(8);

// buffer is empty
assert(buffer.index == 0);
assert(buffer.length == 0);
assert(buffer.data!ubtye == []);

buffer.write(1);
buffer.write(2);
assert(buffer.index == 0); // not increased
assert(buffer.length == 8);

buffer.read!int();
assert(buffer.index == 4); // increased
assert(buffer.length == 8);
```

### peeking

Peeking is the same as reading, except it doesn't increase the reading index.

```d
Buffer buffer = new Buffer(4);
buffer.write(1);

auto data = buffer.data!ubyte;
assert(buffer.peek!int() == 1);
assert(buffer.data!ubyte == data);

assert(buffer.peek!int() == buffer.read!int());
```

## Typed Buffer

`Typed` is a utility template that provides methods and properties to simplify the use of a buffer with a single type of data.

```d
alias ByteBuffer = Typed!ubyte;
alias StringBuffer = Typed!string; // or Typed!(immutable(char))
```

`put`, `get` and `get(size_t)` can be used to write and read data or arrays of data, in addition of all the methods provided by `Buffer`, which the typed buffer extends.
