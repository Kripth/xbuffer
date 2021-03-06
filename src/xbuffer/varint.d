﻿module xbuffer.varint;

import std.traits : isIntegral, isSigned, isUnsigned, Unsigned;

import xbuffer.buffer : Buffer;

enum isVar(T) = is(T == Var!V, V);

// debug
import std.stdio : writeln;

unittest {
	
	static assert(isVar!varshort);
	static assert(!isVar!short);
	
}

/**
 * Utility container for reading and writing signed and unsigned
 * varints from Google's protocol buffer.
 */
struct Var(T) if(isIntegral!T && T.sizeof > 1) {
	
	alias Base = T;
	
	static if(isSigned!T) private alias U = Unsigned!T;
	else private enum size_t limit = T.sizeof * 8 / 7 + 1;
	
	@disable this();
	
	static void encode(Buffer buffer, T value) pure nothrow @safe @nogc {
		static if(isUnsigned!T) {
			while(value > 0x7F) {
				buffer.write!ubyte((value & 0x7F) | 0x80);
				value >>>= 7;
			}
			buffer.write!ubyte(value & 0x7F);
		} else {
			static if(T.sizeof < int.sizeof) Var!U.encode(buffer, cast(U)(value >= 0 ? value << 1 : (-cast(int)value << 1) - 1));
			else Var!U.encode(buffer, value >= 0 ? value << 1 : (-value << 1) - 1);
		}
	}

	static T decode(bool consume)(Buffer buffer) pure @safe {
		size_t count = 0;
		static if(!consume) scope(success) buffer.back(count);
		return decodeImpl(buffer, count);
	}

	static T decodeImpl(Buffer buffer, ref size_t count) pure @safe {
		static if(isUnsigned!T) {
			scope(failure) buffer.back(count);
			T ret;
			ubyte next;
			do {
				next = buffer.read!ubyte();
				ret |= T(next & 0x7F) << (count++ * 7);
			} while(next > 0x7F && count < limit);
			return ret;
		} else {
			U ret = Var!U.decodeImpl(buffer, count);
			if(ret & 1) return ((ret >> 1) + 1) * -1;
			else return ret >> 1;
		}
	}
	
}

alias varshort = Var!short;

alias varushort = Var!ushort;

alias varint = Var!int;

alias varuint = Var!uint;

alias varlong = Var!long;

alias varulong = Var!ulong;

unittest {
	
	Buffer buffer = new Buffer(16);
	
	varint.encode(buffer, 0);
	assert(buffer.data!ubyte == [0]);
	
	buffer.reset();
	varshort.encode(buffer, -1);
	varint.encode(buffer, 1);
	varint.encode(buffer, -2);
	assert(buffer.data!ubyte == [1, 2, 3]);
	
	buffer.reset();
	varint.encode(buffer, 2147483647);
	varint.encode(buffer, -2147483648);
	assert(buffer.data!ubyte == [254, 255, 255, 255, 15, 255, 255, 255, 255, 15]);

	assert(varint.decode!true(buffer) == 2147483647);
	assert(varint.decode!true(buffer) == -2147483648);
	
	buffer.data = cast(ubyte[])[1, 2, 3];
	assert(varint.decode!false(buffer) == -1);
	assert(varint.decode!true(buffer) == -1);
	assert(varint.decode!true(buffer) == 1);
	assert(varint.decode!true(buffer) == -2);
	
	varuint.encode(buffer, 1);
	varuint.encode(buffer, 2);
	varuint.encode(buffer, uint.max);
	assert(buffer.data!ubyte == [1, 2, 255, 255, 255, 255, 15]); 
	assert(varushort.decode!true(buffer) == 1);
	assert(varuint.decode!true(buffer) == 2);
	assert(varulong.decode!true(buffer) == uint.max);

	// limit

	buffer.data = cast(ubyte[])[255, 255, 255, 255, 255, 255];
	varuint.decode!true(buffer);
	assert(buffer.data!ubyte == [255]);

	// exception

	import xbuffer.buffer : BufferOverflowException;

	buffer.data = cast(ubyte[])[255, 255, 255];
	try {
		varuint.decode!true(buffer); assert(0);
	} catch(BufferOverflowException) {
		assert(buffer.data!ubyte == [255, 255, 255]);
		varushort.decode!true(buffer);
		assert(buffer.data.length == 0);
	}
	
}
