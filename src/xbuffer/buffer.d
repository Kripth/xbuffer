module xbuffer.buffer;

import std.bitmanip : swapEndian;
import std.string : toUpper;
import std.system : Endian, endian;
import std.traits : isArray, isBoolean, isIntegral, isFloatingPoint, isSomeChar, Unqual;

import xbuffer.memory : malloc, realloc, _free = free;
import xbuffer.varint : isVar, Var;

//TODO remove
import std.stdio : writeln;

alias ForeachType(T) = typeof(T.init[0]);

enum canSwapEndianness(T) = isBoolean!T || isIntegral!T || isFloatingPoint!T || isSomeChar!T || (is(T == struct) && canSwapEndiannessImpl!T);

private bool canSwapEndiannessImpl(T)() {
	static if(is(T == struct)) {
		import std.traits : Fields;
		bool ret = true;
		foreach(field ; Fields!T) {
			if(!canSwapEndianness!field) ret = false;
		}
		return ret;
	} else {
		return false;
	}
}

unittest {
	
	static assert(canSwapEndianness!byte);
	static assert(canSwapEndianness!int);
	static assert(canSwapEndianness!double);
	static assert(canSwapEndianness!char);
	static assert(canSwapEndianness!dchar);
	
}

unittest {
	
	static struct A {}
	
	static struct B { int a, b; }
	
	static class C {}
	
	static struct D { int a; B b; }
	
	static struct E { B b; C c; }
	
	static struct F { void a(){} float b; }
	
	static struct G { @property Object a(){ return null; } }
	
	static struct H { ubyte[] a; }
	
	static struct I { int* a; }
	
	static assert(canSwapEndianness!A);
	static assert(canSwapEndianness!B);
	static assert(!canSwapEndianness!C);
	static assert(canSwapEndianness!D);
	static assert(!canSwapEndianness!E);
	static assert(canSwapEndianness!F);
	static assert(canSwapEndianness!G);
	static assert(!canSwapEndianness!H);
	static assert(!canSwapEndianness!I);
	
}

private union EndianSwapper(T) if(canSwapEndianness!T) {
	
	enum builtInSwap = T.sizeof == 2 || T.sizeof == 4 || T.sizeof == 8;
	
	T value;
	void[T.sizeof] data;
	ubyte[T.sizeof] bytes;
	
	static if(T.sizeof == 2) ushort _swap;
	else static if(T.sizeof == 4) uint _swap;
	else static if(T.sizeof == 8) ulong _swap;
	
	void swap() {
		static if(builtInSwap) _swap = swapEndian(_swap);
		else static if(T.sizeof > 1) {
			import std.algorithm.mutation : swap;
			foreach(i ; 0..T.sizeof>>1) {
				swap(bytes[i], bytes[T.sizeof-i-1]);
			}
		}
	}
	
}

unittest {
	
	static struct Test {
		
		int a, b, c;
		
	}
	
	static assert(Test.sizeof == 12);
	
	EndianSwapper!Test swapper;
	swapper.value = Test(1, 2, 3);
	
	version(BigEndian) assert(swapper.bytes == [0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3]);
	version(LittleEndian) assert(swapper.bytes == [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]);
	
	swapper.swap();
	
	version(BigEndian) assert(swapper.bytes == [3, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0]);
	version(LittleEndian) assert(swapper.bytes == [0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0, 1]);
	
	assert(swapper.value == Test(3 << 24, 2 << 24, 1 << 24));
	
}

/**
 * Exception thrown when the buffer cannot read the requested
 * data.
 */
class BufferOverflowException : Exception {
	
	this(string file=__FILE__, size_t line=__LINE__) pure nothrow @safe @nogc {
		super("The buffer's index has exceeded its length", file, line);
	}
	
}

static if(__traits(compiles, () @nogc { throw new Exception(""); })) version = DIP1008;

/**
 * Buffer for writing and reading binary data.
 */
class Buffer {
	
	private immutable size_t chunk;
	
	private void[] _data;
	private size_t _index = 0;
	private size_t _length = 0;
	
	/**
	 * Creates a buffer specifying the chunk size.
	 * This should be the default constructor for re-used buffers and
	 * input buffers.
	 */
	this(size_t chunk) pure nothrow @safe @nogc {
		this.chunk = chunk;
		_data = malloc(chunk);
	}
	
	///
	pure nothrow @safe unittest {
		
		Buffer buffer = new Buffer(8);
		
		// 8 bytes allocated by the constructor
		assert(buffer.capacity == 8);
		
		// writing 4 bytes does not alter the capacity
		buffer.write(0);
		assert(buffer.capacity == 8);
		
		// writing 8 bytes requires a new allocation (because 4 + 8 is
		// higher than the current capacity of 8).
		// The new capacity is rounded up to the nearest multiple of the chunk size.
		buffer.write(0L);
		assert(buffer.capacity == 16);
		
	}
	
	/**
	 * Creates a buffer from an array of data.
	 * The chunk size is set to the size of array.
	 */
	this(T)(in T[] data...) pure nothrow @trusted @nogc if(canSwapEndianness!T) {
		this(data.length * T.sizeof);
		_length = _data.length;
		_data[0..$] = cast(void[])data;
	}
	
	///
	pure nothrow @safe unittest {
		
		Buffer buffer = new Buffer(cast(ubyte[])[1, 2, 3, 4]);
		assert(buffer.index == 0);
		assert(buffer.length == 4);
		
		buffer = new Buffer([1, 2]);
		assert(buffer.index == 0);
		assert(buffer.length == 8);
		
	}
	
	private void resize(size_t requiredSize) pure nothrow @trusted @nogc {
		immutable rem = requiredSize / chunk;
		immutable size = (requiredSize + chunk - 1) / chunk * chunk;
		_data = realloc(_data.ptr, size);
	}
	
	@property T[] data(T)() pure nothrow @trusted @nogc if((canSwapEndianness!T || is(T == void)) && T.sizeof == 1) {
		return cast(T[])_data[_index.._length];
	}

	@property T[] data(T)() pure nothrow @nogc if(canSwapEndianness!T && T.sizeof != 1) {
		return cast(T[])_data[_index.._length];
	}
	
	/**
	 * Sets new data and resets the index.
	 */
	@property T[] data(T)(T[] data) pure nothrow @trusted @nogc {
		_index = 0;
		_length = data.length * T.sizeof;
		if(_length > _data.length) this.resize(_length);
		_data[0.._length] = cast(void[])data;
		return data;
	}
	
	///
	pure nothrow @trusted unittest {
		
		Buffer buffer = new Buffer(2);
		buffer.data = cast(ubyte[])[0, 0, 0, 1];
		assert(buffer.index == 0); // resetted when setting new data
		assert(buffer.length == 4);
		version(BigEndian) assert(buffer.data!uint == [1]);
		version(LittleEndian) assert(buffer.data!uint == [1 << 24]);
		
	}
	
	/**
	 * Gets the current write/read index of the buffer.
	 * The index can be set to 0 using the `reset` method.
	 */
	@property size_t index() pure nothrow @safe @nogc {
		return _index;
	}
	
	/**
	 * Gets the length of the buffer.
	 */
	@property size_t length() pure nothrow @safe @nogc {
		return _length;
	}
	
	/**
	 * Resets the buffer setting the index and its length to 0.
	 */
	void reset() pure nothrow @safe @nogc {
		_index = 0;
		_length = 0;
	}
	
	/**
	 * Gets the size of the data allocated by the buffer.
	 */
	@property size_t capacity() pure nothrow @safe @nogc {
		return _data.length;
	}

	// ----------
	// operations
	// ----------

	/**
	 * Check whether the data of the buffer is equals to
	 * the given array.
	 */
	bool opEquals(T)(T[] data) pure nothrow @safe @nogc if(T.sizeof == 1) {
		return this.data!T == data;
	}

	/// ditto
	bool opEquals(T)(T[] data) pure nothrow @nogc if(T.sizeof != 1) {
		return this.data!T == data;
	}

	///
	pure nothrow @trusted unittest {

		Buffer buffer = new Buffer([1, 2, 3]);

		assert(buffer == [1, 2, 3]);
		version(BigEndian) assert(buffer == cast(ubyte[])[0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3]);
		version(LittleEndian) assert(buffer == cast(ubyte[])[1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]);

	}
	
	// -----
	// write
	// -----
	
	private void need(size_t size) pure nothrow @safe @nogc {
		size += _length;
		if(size > this.capacity) this.resize(size);
	}
	
	private void writeDataImpl(in void[] data) pure nothrow @trusted @nogc {
		immutable start = _length;
		_length += data.length;
		_data[start.._length] = data;
	}
	
	/**
	 * Writes data to the buffer and expands if it is not big enough.
	 */
	void writeData(in void[] data) pure nothrow @safe @nogc {
		this.need(data.length);
		this.writeDataImpl(data);
	}
	
	/**
	 * Writes data to buffer using the given endianness.
	 */
	void write(Endian endianness, T)(T value) pure nothrow @trusted @nogc if(canSwapEndianness!T) {
		EndianSwapper!T swapper = EndianSwapper!T(value);
		static if(endianness != endian && T.sizeof > 1) swapper.swap();
		this.writeData(swapper.data);
	}
	
	///
	unittest {
		
		Buffer buffer = new Buffer(4);
		buffer.write!(Endian.bigEndian)(4);
		buffer.write!(Endian.littleEndian)(4);
		assert(buffer.data!ubyte == [0, 0, 0, 4, 4, 0, 0, 0]);
		
	}
	
	/**
	 * Writes data to the buffer using the system's endianness.
	 */
	void write(T)(T value) pure nothrow @safe @nogc if(canSwapEndianness!T) {
		this.write!(endian, T)(value);
	}
	
	///
	pure nothrow @safe unittest {
		
		Buffer buffer = new Buffer(5);
		buffer.write(ubyte(5));
		buffer.write(10);
		version(BigEndian) assert(buffer.data!ubyte == [5, 0, 0, 0, 10]);
		version(LittleEndian) assert(buffer.data!ubyte == [5, 10, 0, 0, 0]);
		
	}
	
	/**
	 * Writes an array using the given endianness.
	 */
	void write(Endian endianness, T)(in T value) pure nothrow @trusted @nogc if(isArray!T && (is(ForeachType!T : void) || canSwapEndianness!(ForeachType!T))) {
		static if(endianness == endian || T.sizeof <= 1) {
			this.writeData(value);
		} else {
			this.need(value.length * ForeachType!T.sizeof);
			foreach(element ; value) {
				auto swapper = EndianSwapper!(ForeachType!T)(element);
				swapper.swap();
				this.writeDataImpl(swapper.data);
			}
		}
	}
	
	///
	pure nothrow @safe unittest {
		
		Buffer buffer = new Buffer(8);
		buffer.write!(Endian.bigEndian)([1, 2, 3]);
		assert(buffer.capacity == 16);
		assert(buffer.data!ubyte == [0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3]);
		
		buffer.reset();
		buffer.write!(Endian.littleEndian)(cast(short[])[-2, 2]);
		assert(buffer.data!ubyte == [254, 255, 2, 0]);
		
	}
	
	/**
	 * Writes an array using the system's endianness.
	 */
	void write(T)(in T value) pure nothrow @safe @nogc if(isArray!T && (is(ForeachType!T : void) || canSwapEndianness!(ForeachType!T))) {
		this.write!(endian, T)(value);
	}
	
	///
	pure nothrow @safe unittest {
		
		Buffer buffer = new Buffer(8);
		buffer.write(cast(ubyte[])[1, 2, 3, 4]);
		buffer.write("test");
		assert(buffer.data!ubyte == [1, 2, 3, 4, 't', 'e', 's', 't']);
		buffer.write([1, 2]);
		version(BigEndian) assert(buffer.data!ubyte == [1, 2, 3, 4, 't', 'e', 's', 't', 0, 0, 0, 1, 0, 0, 0, 2]);
		version(LittleEndian) assert(buffer.data!ubyte == [1, 2, 3, 4, 't', 'e', 's', 't', 1, 0, 0, 0, 2, 0, 0, 0]);
		
	}
	
	/**
	 * Writes a varint.
	 */
	void writeVar(T)(T value) pure nothrow @safe @nogc if(isIntegral!T && T.sizeof > 1) {
		Var!T.encode(this, value);
	}

	/// ditto
	void write(T:Var!B, B)(B value) pure nothrow @safe @nogc {
		this.writeVar!(T.Base)(value);
	}
	
	///
	pure nothrow @safe unittest {
		
		import xbuffer.varint;
		
		Buffer buffer = new Buffer(8);
		buffer.writeVar(1);
		buffer.write!varuint(1);
		assert(buffer.data!ubyte == [2, 1]);
		
	}
	
	// ----
	// read
	// ----
	
	/**
	 * Indicates whether an array of length `size` or the given type
	 * can be read without any exceptions thrown.
	 */
	bool canRead(size_t size) pure nothrow @safe @nogc {
		return _index + size <= _length;
	}
	
	/// ditto
	bool canRead(T)() pure nothrow @safe @nogc if(canSwapEndianness!T) {
		return this.canRead(T.sizeof);
	}
	
	///
	unittest {
		
		import xbuffer.varint;
		
		Buffer buffer = new Buffer(cast(ubyte[])[128, 200, 3]);
		assert(buffer.canRead(2));
		assert(buffer.canRead(3));
		assert(!buffer.canRead(4));
		assert(buffer.canRead!byte());
		assert(buffer.canRead!short());
		assert(!buffer.canRead!int());
		
	}
	
	void[] readData(size_t size) pure @safe {
		if(!this.canRead(size)) throw new BufferOverflowException();
		_index += size;
		return _data[_index-size.._index];
	}
	
	pure @safe unittest {
		
		Buffer buffer = new Buffer([1]);
		assert(buffer.read!int() == 1);
		try {
			buffer.read!int(); assert(0);
		} catch(BufferOverflowException ex) {
			assert(ex.file == __FILE__);
		}
		
	}
	
	/**
	 * Reads a value using the system's endianness.
	 */
	T read(T)() pure @trusted if(canSwapEndianness!T) {
		EndianSwapper!T swapper;
		swapper.data = this.readData(T.sizeof);
		return swapper.value;
	}
	
	///
	pure @safe unittest {
		
		version(BigEndian) Buffer buffer = new Buffer([0, 0, 0, 1]);
		version(LittleEndian) Buffer buffer = new Buffer([1, 0, 0, 0]);
		assert(buffer.read!int() == 1);
		
	}
	
	/**
	 * Reads an array.
	 */
	T read(T)(size_t size) pure @trusted if(isArray!T && ForeachType!T.sizeof == 1) {
		return cast(T)this.readData(size);
	}
	
	///
	pure @safe unittest {
		
		Buffer buffer = new Buffer("!hello");
		assert(buffer.read!(ubyte[])(1) == [33]);
		assert(buffer.read!string(5) == "hello");
		
	}
	
	/**
	 * Reads an array using the system's endianness.
	 */
	T read(T)(size_t size) pure @trusted if(isArray!T && ForeachType!T.sizeof > 1) {
		return cast(T)this.readData(size * ForeachType!T.sizeof);
	}
	
	///
	unittest {
		
		version(BigEndian) Buffer buffer = new Buffer(cast(ubyte[])[0, 0, 0, 1, 0, 0, 0, 2]);
		version(LittleEndian) Buffer buffer = new Buffer(cast(ubyte[])[1, 0, 0, 0, 2, 0, 0, 0]);
		assert(buffer.read!(int[])(2) == [1, 2]);
		
	}
	
	///
	unittest {
		
		struct Test { int a; }
		
		Buffer buffer = new Buffer(Test(1), Test(2), Test(3));
		assert(buffer.read!(Test[])(3) == [Test(1), Test(2), Test(3)]);
		
	}
	
	/**
	 * Reads a type, specifying the endianness.
	 */
	T read(Endian endianness, T)() pure @trusted if(canSwapEndianness!T) {
		static if(endianness == endian) return this.read!T();
		else {
			EndianSwapper!T swapper;
			swapper.data = this.readData(T.sizeof);
			swapper.swap();
			return swapper.value;
		}
	}
	
	///
	unittest {
		
		Buffer buffer = new Buffer(cast(ubyte[])[0, 0, 0, 1, 1, 0]);
		assert(buffer.read!(Endian.bigEndian, int)() == 1);
		assert(buffer.read!(Endian.littleEndian, short)() == 1);
		
	}
	
	/**
	 * Reads a varint.
	 */
	T readVar(T)() pure @safe if(isIntegral!T && T.sizeof > 1) {
		return Var!T.decode(this);
	}
	
	/// ditto
	B read(T:Var!B, B)() pure @safe {
		return this.readVar!B();
	}
	
	///
	unittest {
		
		import xbuffer.varint;
		
		Buffer buffer = new Buffer(cast(ubyte[])[2, 1]);
		assert(buffer.readVar!int() == 1);
		assert(buffer.read!varuint() == 1);
		
	}
	
	// ----
	// peek
	// ----
	
	void[] peekData(size_t size) pure {
		if(!this.canRead(size)) throw new BufferOverflowException();
		return _data[_index.._index+size];
	}
	
	unittest {
		
		Buffer buffer = new Buffer([1]);
		buffer.peekData(4);
		assert(buffer.index == 0);
		
	}
	
	/**
	 * Peeks a value using the system's endianness.
	 */
	T peek(T)() pure if(canSwapEndianness!T) {
		EndianSwapper!T swapper;
		swapper.data = this.peekData(T.sizeof);
		return swapper.value;
	}
	
	///
	unittest {
		
		Buffer buffer = new Buffer([1, 2]);
		assert(buffer.peek!int() == 1);
		assert(buffer.index == 0);
		assert(buffer.peek!int() == buffer.read!int());
		assert(buffer.index == 4);
		assert(buffer.peek!int() == 2);
		
	}
	
	// destruction
	
	void free() pure nothrow @nogc {
		_free(_data.ptr);
	}
	
	void __xdtor() pure nothrow @nogc {
		this.free();
	}
	
	~this() {
		this.free();
	}
	
}

///
unittest {
	
	import xbuffer.memory;
	
	// a buffer can be garbage collected
	Buffer gc = new Buffer(16);
	
	// or manually allocated
	// alloc is a function provided by the xbuffer.memory module
	Buffer b = alloc!Buffer(16);
	
	// the memory is realsed with free, which is called by the garbage
	// collector of by the `free` function in the `xbuffer.memory` module
	free(b);
	
}

unittest {
	
	import xbuffer.memory;
	
	void[] data = calloc(923);
	
	auto buffer = alloc!Buffer(1024);
	assert(buffer.length == 0);
	
	buffer.writeData(data);
	assert(buffer.index == 0);
	assert(buffer.length == 923);
	assert(buffer.capacity == 1024);
	
	buffer.writeData(data);
	assert(buffer.length == 1846);
	assert(buffer.capacity == 2048);
	
	data = realloc(data.ptr, 1);
	
	buffer.data = data;
	assert(buffer.length == 1);
	assert(buffer.capacity == 2048);
	
	data = realloc(data.ptr, 2049);
	
	buffer.data = data;
	assert(buffer.length == 2049);
	assert(buffer.capacity == 3072);
	
	free(data.ptr);
	free(buffer);
	
}
