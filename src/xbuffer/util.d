module xbuffer.util;

import std.system : Endian, endian;

import xbuffer.buffer : Buffer, canSwapEndianness;

/**
 * Extension template for a buffer that provides methods
 * and properties useful for working with a single type
 * of data.
 */
class Typed(T, B:Buffer=Buffer) : B if(canSwapEndianness!T) {
	
	this(size_t chunk) pure nothrow @safe @nogc {
		super(chunk * T.sizeof);
	}
	
	this(in T[] data) pure nothrow @safe @nogc {
		super(data);
	}
	
	/**
	 * Gets the data as an array of the template's type.
	 * The data can also be obtained in the specified format.
	 * Example:
	 * ---
	 * auto buffer = new Typed!char("hello");
	 * assert(buffer.data == "hello");
	 * assert(buffer.data!ubyte == [104, 101, 108, 108, 111]);
	 * ---
	 */
	@property D[] data(D=T)() pure nothrow @trusted @nogc if(D.sizeof == 1) {
		return super.data!D;
	}
	
	/// ditto
	@property D[] data(D=T)() pure nothrow @nogc if(D.sizeof != 1) {
		return super.data!D;
	}
	
	/**
	 * Writes a value of type `T` or array of type `T[]`.
	 * Example:
	 * ---
	 * auto buffer = new Typed!short(4);
	 * buffer.put(1);
	 * buffer.put(2, 3);
	 * buffer.put([4, 5]);
	 * assert(buffer.data == [1, 2, 3, 4, 5]);
	 * ---
	 */
	void put(T value) pure nothrow @safe @nogc {
		this.write(value);
	}
	
	/// ditto
	void put(in T[] value...) pure nothrow @safe @nogc {
		this.write(value);
	}
	
	/**
	 * Reads a value of type `T` or an array of type `T[]`.
	 * Example:
	 * ---
	 * auto buffer = new Typed!int(4);
	 * buffer.data = [1, 2, 3, 4, 5];
	 * assert(buffer.get == 1);
	 * assert(buffer.get == 2);
	 * assert(buffer.get(3) == [3, 4, 5]);
	 * ---
	 */
	T get() pure @safe {
		return this.read!T();
	}
	
	/// ditto
	T[] get(size_t length) pure @safe {
		return this.read!(T[])(length);
	}
	
}

///
unittest {
	
	alias ByteBuffer = Typed!ubyte;
	
	auto buffer = new ByteBuffer([0, 0, 0, 4]);
	assert(buffer.read!(Endian.bigEndian, uint)() == 4);
	
	buffer.reset();
	buffer.put(1);
	buffer.put([2, 3]);
	buffer.put(4, 5, 6);
	assert(buffer.data == [1, 2, 3, 4, 5, 6]);
	assert(buffer.get == 1);
	assert(buffer.get(3) == [2, 3, 4]);
	
}

///
unittest {
	
	alias IntBuffer = Typed!int;
	
	auto buffer = new IntBuffer(2);
	assert(buffer.capacity == 8);
	buffer.write(1);
	buffer.write(2);
	version(BigEndian) assert(buffer.data!ubyte == [0, 0, 0, 1, 0, 0, 0, 2]);
	version(LittleEndian) assert(buffer.data!ubyte == [1, 0, 0, 0, 2, 0, 0, 0]);
	assert(buffer.read!int() == 1);
	assert(buffer.read!int() == 2);
	
}

///
unittest {
	
	static struct Test {
		
		int a;
		short b;
		
	}
	
	static assert(Test.sizeof == 8); // because of the alignment
	
	alias TestBuffer = Typed!Test;
	
	auto buffer = new TestBuffer(1);
	buffer.put(Test(1, 2));
	version(BigEndian) assert(buffer.data!ubyte == [0, 0, 0, 1, 0, 2, 0, 0]);
	version(LittleEndian) assert(buffer.data!ubyte == [1, 0, 0, 0, 2, 0, 0, 0]);
	assert(buffer.data == [Test(1, 2)]);
	assert(buffer.get == Test(1, 2));
	
	buffer.reset();
	buffer.write!(cast(Endian)!endian)(Test(1, 2));
	version(BigEndian) assert(buffer.data!ubyte == [0, 0, 2, 0, 1, 0, 0, 0]);
	version(LittleEndian) assert(buffer.data!ubyte == [0, 0, 0, 2, 0, 0, 0, 1]);
	
}

///
unittest {
	
	static struct Test {
		
		int a;
		ubyte[] b;
		
	}
	
	static assert(!canSwapEndianness!Test);
	
}
